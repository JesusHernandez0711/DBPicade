/* ====================================================================================================
   PROCEDIMIENTO: SP_CambiarEstatusParticipante (Gestor de Ciclo de Vida)                    
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. MANIFIESTO DE PROPÓSITO Y CONTEXTO OPERATIVO (THE "WHY")
   ----------------------------------------------------------------------------------------------------
   [DEFINICIÓN DEL COMPONENTE]:
   Este Stored Procedure (SP) no es un simple script de actualización. Es el **Gobernador de Disponibilidad**
   del catálogo `Cat_Estatus_Participante`. Su responsabilidad es administrar la transición de estados
   entre "Operativo" (1) y "Obsoleto/Baja Lógica" (0).

   [EL PROBLEMA DE LA "HISTORIA VIVA" (THE LIVE HISTORY PROBLEM)]:
   En este sistema, la tabla `Capacitaciones_Participantes` actúa como una bitácora histórica inmutable
   (no tiene borrado lógico). Esto presenta un desafío único para la integridad referencial:
   
   * Si desactivamos el estatus "INSCRITO", ¿qué pasa con los alumnos que están en clase AHORA MISMO?
   
   No podemos simplemente preguntar "¿Este estatus se ha usado antes?". La respuesta siempre será SÍ.
   Debemos preguntar: **"¿Este estatus se está usando en un proceso VIVO en este preciso segundo?"**

   [SOLUCIÓN: EL KILLSWITCH FORENSE DINÁMICO]:
   Implementamos un algoritmo de **Validación de Integridad Transitiva de 4 Niveles**:
   1.  Nivel 1 (El Estatus): ¿Quién lo tiene asignado?
   2.  Nivel 2 (El Alumno): ¿A qué capacitación pertenece ese alumno?
   3.  Nivel 3 (La Vida del Curso): ¿El registro del curso está activo (`Activo=1`)?
   4.  Nivel 4 (La Fase del Curso): ¿El curso está en una etapa operativa (No Final)?

   Solo si se superan los 4 niveles de riesgo, se bloquea la desactivación. De lo contrario, se permite
   archivar el estatus como "historia antigua".

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE REGLAS DE BLINDAJE (HARD CONSTRAINTS)
   ----------------------------------------------------------------------------------------------------
   [RN-01] INTEGRIDAD DE DOMINIO (INPUT HYGIENE):
      - Principio: "Calidad a la entrada, calidad a la salida".
      - Mecanismo: Se rechazan explícitamente valores NULL o fuera del rango binario [0,1].
      - Objetivo: Prevenir comportamientos indefinidos por lógica trivalente de SQL.

   [RN-02] AISLAMIENTO SERIALIZABLE (ACID CONCURRENCY):
      - Principio: "Un solo escritor a la vez".
      - Mecanismo: Uso de `SELECT ... FOR UPDATE` (Bloqueo Pesimista / Pessimistic Locking).
      - Objetivo: Evitar la "Condición de Carrera" (Race Condition) donde dos administradores
        intentan modificar el mismo estatus simultáneamente.

   [RN-03] IDEMPOTENCIA DE ESTADO (RESOURCE OPTIMIZATION):
      - Principio: "Si no está roto, no lo arregles".
      - Mecanismo: Si el estado en disco ya es igual al solicitado, se aborta la escritura.
      - Objetivo: Reducir I/O de disco, evitar crecimiento del Transaction Log y preservar la
        fidelidad forense del campo `updated_at`.

   [RN-04] PROTOCOLO DE DESACTIVACIÓN SEGURA (SAFE DELETE):
      - Principio: "No apagues la luz si hay gente operando".
      - Mecanismo: Escaneo profundo de dependencias vivas mediante JOINs.
      - Acción: Error 409 (Conflict) si se detectan dependencias activas.

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA (TECHNICAL SPECS)
   ----------------------------------------------------------------------------------------------------
   - TIPO: Transacción Atómica.
   - SCOPE: `Cat_Estatus_Participante` (Target), `Capacitaciones_Participantes` (Dependency),
            `DatosCapacitaciones` (Context), `Cat_Estatus_Capacitacion` (Logic).
   - OUTPUT: JSON-Structure Resultset { Mensaje, Accion, Estado_Nuevo, Estado_Anterior, Id }.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_CambiarEstatusParticipante`$$

CREATE PROCEDURE `SP_CambiarEstatusParticipante`(
    /* ------------------------------------------------------------------------------------------------
       SECCIÓN A: CAPA DE ENTRADA (INPUT PARAMETERS)
       Recibimos los datos atómicos necesarios para ejecutar la transacción.
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Estatus    INT,       -- [OBLIGATORIO] Identificador Único (PK) del estatus a modificar.
    IN _Nuevo_Estatus TINYINT    -- [OBLIGATORIO] Bandera de estado deseado (1=Activar, 0=Desactivar).
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       SECCIÓN B: DECLARACIÓN DE VARIABLES Y CONTEXTO (VARIABLE SCOPE)
       Definimos los contenedores de memoria necesarios para el procesamiento lógico.
       ============================================================================================ */
    
    /* [B.1] Variables de Snapshot (Estado Previo):
       Almacenan la "foto" del registro tal como existe en disco antes de tocarlo.
       Vitales para la lógica de Idempotencia y para construir mensajes de error humanos. */
    DECLARE v_Nombre_Actual VARCHAR(255) DEFAULT NULL; -- Nombre descriptivo (ej: 'APROBADO')
    DECLARE v_Activo_Actual TINYINT      DEFAULT NULL; -- Estado actual (0 o 1)
    
    /* [B.2] Semáforo Forense (Integrity Flag):
       Variable crítica que almacenará el conteo de conflictos de integridad encontrados.
       Si este valor > 0, significa que hay riesgo operativo y debemos abortar. */
    DECLARE v_Dependencias_Vivas INT DEFAULT 0;

    /* [B.3] Variables de Diagnóstico (Debugging):
       Utilizadas para construir el mensaje de error detallado en caso de bloqueo. */
    DECLARE v_Folio_Curso_Conflicto VARCHAR(50) DEFAULT NULL; -- Para decirle al usuario QUÉ curso estorba.
    DECLARE v_Estado_Curso_Conflicto VARCHAR(255) DEFAULT NULL; -- Para decirle EN QUÉ estado está.

    /* [B.4] Buffer de Mensajería:
       Almacena el texto final que se enviará al cliente. */
    DECLARE v_Mensaje_Final TEXT;

    /* ============================================================================================
       SECCIÓN C: GESTIÓN DE EXCEPCIONES Y SEGURIDAD (SAFETY NET)
       Configuración de handlers para asegurar una salida limpia ante errores catastróficos.
       ============================================================================================ */
    
    /* [C.1] Handler Genérico (SQLEXCEPTION):
       Captura cualquier error no controlado (Deadlocks, Timeout, Disco Lleno, Sintaxis).
       ACCIÓN:
         1. ROLLBACK: Revertir cualquier cambio parcial.
         2. RESIGNAL: Propagar el error original al backend para que quede en el log del servidor. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       SECCIÓN D: VALIDACIONES PREVIAS (FAIL FAST STRATEGY)
       Protegemos la base de datos rechazando peticiones "basura" antes de iniciar la transacción.
       ============================================================================================ */
    
    /* [D.1] Validación de Integridad de Identidad:
       El ID debe ser un número entero positivo. Un ID negativo o nulo es un error de sistema. */
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de Estatus proporcionado es inválido o nulo.';
    END IF;

    /* [D.2] Validación de Dominio Estricta:
       El estatus es un valor binario. SQL permite NULL, pero nuestra lógica de negocio NO.
       Rechazamos explícitamente los Nulos para evitar lógica trivalente peligrosa. */
    IF _Nuevo_Estatus IS NULL OR _Nuevo_Estatus NOT IN (0, 1) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: El parámetro _Nuevo_Estatus es obligatorio y solo acepta valores binarios: 0 (Inactivo) o 1 (Activo).';
    END IF;

    /* ============================================================================================
       SECCIÓN E: INICIO DE TRANSACCIÓN Y AISLAMIENTO (ACID BEGINS)
       A partir de este punto, entramos en modo "Atomicidad". O todo ocurre, o nada ocurre.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO E.1: ADQUISICIÓN DE SNAPSHOT CON BLOQUEO (PESSIMISTIC LOCK)
       
       [QUÉ HACE]: Ejecuta un `SELECT ... FOR UPDATE`.
       
       [POR QUÉ LO HACEMOS]:
       Necesitamos "congelar" el tiempo para este registro. 
       - Imaginemos que el Admin A intenta desactivar el estatus.
       - Al mismo tiempo, el Admin B intenta cambiarle el nombre a "PENDIENTE URGENTE".
       - Sin bloqueo, podríamos desactivar un estatus que acaba de cambiar de significado.
       
       [EFECTO TÉCNICO]:
       InnoDB coloca un candado exclusivo (X-Lock) en la fila del índice primario.
       Nadie más puede leer (en modo lock) o escribir en esta fila hasta que terminemos.
       -------------------------------------------------------------------------------------------- */
    SELECT `Nombre`, `Activo`
    INTO v_Nombre_Actual, v_Activo_Actual
    FROM `Cat_Estatus_Participante`
    WHERE `Id_CatEstPart` = _Id_Estatus
    LIMIT 1
    FOR UPDATE;

    /* --------------------------------------------------------------------------------------------
       PASO E.2: VALIDACIÓN DE EXISTENCIA (NOT FOUND)
       Si las variables siguen siendo NULL después del SELECT, el registro no existe físicamente.
       -------------------------------------------------------------------------------------------- */
    IF v_Nombre_Actual IS NULL THEN
        ROLLBACK; -- Liberamos recursos del lock inmediatamente.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus solicitado no existe en el catálogo maestro. Pudo haber sido eliminado previamente.';
    END IF;

    /* --------------------------------------------------------------------------------------------
       PASO E.3: VERIFICACIÓN DE IDEMPOTENCIA (OPTIMIZACIÓN)
       
       [LÓGICA]: "Si ya está encendido, no gastes energía en encenderlo de nuevo".
       
       [BENEFICIO CRÍTICO]: 
       1. **Ahorro de I/O:** No se escribe en disco si no es necesario.
       2. **Integridad de Auditoría:** Si hacemos un UPDATE con los mismos valores, MySQL podría
          actualizar el `updated_at` (dependiendo de la config). Queremos evitar falsos positivos
          de modificación.
       -------------------------------------------------------------------------------------------- */
    IF v_Activo_Actual = _Nuevo_Estatus THEN
        
        COMMIT; -- Liberamos el bloqueo. La transacción termina aquí benignamente.
        
        /* Construimos respuesta informativa */
        SELECT CONCAT('AVISO DE SISTEMA: El Estatus "', v_Nombre_Actual, '" ya se encuentra en el estado solicitado (', IF(_Nuevo_Estatus=1,'ACTIVO','INACTIVO'), '). No se requirieron cambios.') AS Mensaje,
               'SIN_CAMBIOS' AS Accion,
               v_Activo_Actual AS Estado_Anterior,
               _Nuevo_Estatus AS Estado_Nuevo;
        
        LEAVE THIS_PROC; -- Salida limpia y temprana del SP.
    END IF;

    /* ============================================================================================
       SECCIÓN F: ANÁLISIS DE IMPACTO Y KILLSWITCH (THE LOGIC CORE)
       Aquí reside la inteligencia del procedimiento. Decidimos si es seguro proceder.
       ============================================================================================ */
    
    /* --------------------------------------------------------------------------------------------
       CASO F.1: PROTOCOLO DE DESACTIVACIÓN (KILLSWITCH / BAJA LÓGICA)
       Condición: `_Nuevo_Estatus = 0` (El usuario quiere APAGAR el estatus).
       
       [RIESGO]: Dejar "ciegos" a los reportes de cursos actuales.
       [DEFENSA]: Integridad Referencial Transitiva.
       -------------------------------------------------------------------------------------------- */
    IF _Nuevo_Estatus = 0 THEN
        
        /* [CONSULTA FORENSE MULTI-NIVEL]:
           Buscamos si existe AL MENOS UN CASO que impida la desactivación.
           
           Navegación de la consulta:
           1. FROM `Capacitaciones_Participantes` CP: 
              -> ¿Hay alumnos con este estatus? (Histórico y Actual).
              
           2. INNER JOIN `DatosCapacitaciones` DC: 
              -> ¿A qué curso específico pertenecen esos alumnos?
              
           3. INNER JOIN `Capacitaciones` C:
              -> Necesario para obtener el Folio (Numero_Capacitacion) para el error.
              
           4. INNER JOIN `Cat_Estatus_Capacitacion` EC:
              -> EL CEREBRO. Consultamos la bandera `Es_Final`.
              
           5. WHERE ...
              -> CP.Fk... = _Id_Estatus: Filtramos por el estatus que queremos borrar.
              -> DC.Activo = 1: El registro histórico del curso es el vigente.
              -> EC.Es_Final = 0: EL CURSO ESTÁ VIVO (No ha finalizado).
        */
        
        SELECT 
            C.Numero_Capacitacion, -- Evidencia 1: El folio del curso culpable
            EC.Nombre              -- Evidencia 2: El estado del curso (ej: "EN CURSO")
        INTO 
            v_Folio_Curso_Conflicto,
            v_Estado_Curso_Conflicto
        FROM `Capacitaciones_Participantes` CP
        
        /* Conexión con el Historial del Curso */
        INNER JOIN `DatosCapacitaciones` DC ON CP.Fk_Id_DatosCap = DC.Id_DatosCap
        
        /* Conexión con la Cabecera del Curso (Para el Folio) */
        INNER JOIN `Capacitaciones` C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
        
        /* Conexión con el Catálogo de Estatus del Curso (Para la Lógica de Negocio) */
        INNER JOIN `Cat_Estatus_Capacitacion` EC ON DC.Fk_Id_CatEstCap = EC.Id_CatEstCap
        
        WHERE 
            CP.Fk_Id_CatEstPart = _Id_Estatus  -- Buscamos uso de ESTE estatus
            AND DC.Activo = 1                  -- En cursos que no han sido borrados (Soft Delete)
            AND C.Activo = 1                   -- En cabeceras que no han sido borradas
            
            /* --- EL CANDADO MAESTRO --- */
            AND EC.Es_Final = 0                -- Solo nos importan los cursos OPERATIVOS.
                                               -- Si Es_Final=1 (Finalizado/Cancelado), no bloqueamos.
        
        LIMIT 1; -- Con encontrar UN solo conflicto es suficiente para abortar.

        /* [EVALUACIÓN DEL SEMÁFORO]:
           Si las variables de conflicto se llenaron (IS NOT NULL), tenemos un problema. */
        IF v_Folio_Curso_Conflicto IS NOT NULL THEN
            
            ROLLBACK; -- Cancelación inmediata de la transacción. Seguridad ante todo.
            
            /* Construcción del Mensaje Forense:
               Le explicamos al usuario EXACTAMENTE por qué no puede proceder. */
            SET v_Mensaje_Error = CONCAT(
                'BLOQUEO DE INTEGRIDAD [409]: Operación Denegada. ',
                'No se puede desactivar el estatus "', v_Nombre_Actual, '" ',
                'porque está siendo utilizado activamente por participantes en el curso con Folio "', v_Folio_Curso_Conflicto, '" ',
                'que se encuentra actualmente en estado "', v_Estado_Curso_Conflicto, '". ',
                'Este curso se considera OPERATIVO (No Finalizado). ',
                'Para proceder, debe finalizar el curso o cambiar el estatus de los alumnos involucrados.'
            );
                                   
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_Mensaje_Error;
        END IF;
        
        /* Si llegamos aquí, significa que v_Folio_Curso_Conflicto es NULL.
           El estatus puede haber sido usado 1000 veces en el pasado, pero NO se está usando
           en ningún curso vivo hoy. Es seguro proceder. */
    END IF;

    /* --------------------------------------------------------------------------------------------
       CASO F.2: PROTOCOLO DE REACTIVACIÓN (RESURRECTION)
       Condición: `_Nuevo_Estatus = 1` (El usuario quiere PRENDER el estatus).
       
       [ANÁLISIS]:
       Reactivar es seguro. No rompe integridad. Solo vuelve disponible una opción.
       No requiere validaciones adicionales en este diseño.
       -------------------------------------------------------------------------------------------- */
    IF _Nuevo_Estatus = 1 THEN
        -- Pasamos directo a la persistencia.
        SET v_Dependencias_Vivas = 0; 
    END IF;

    /* ============================================================================================
       SECCIÓN G: PERSISTENCIA Y CIERRE (COMMIT PHASE)
       Si el flujo llega a este punto, hemos pasado todas las aduanas de seguridad forense.
       ============================================================================================ */
    
    /* G.1 Ejecución del Cambio de Estado (UPDATE) */
    UPDATE `Cat_Estatus_Participante`
    SET `Activo` = _Nuevo_Estatus,
        `updated_at` = NOW() -- Auditoría: Se marca el momento exacto de la modificación.
    WHERE `Id_CatEstPart` = _Id_Estatus;

    /* G.2 Confirmación de la Transacción */
    COMMIT; -- Los cambios se hacen permanentes y visibles para otros usuarios. Se libera el Lock.

    /* ============================================================================================
       SECCIÓN H: RESPUESTA AL CLIENTE (FEEDBACK LAYER)
       Generamos un mensaje humano que confirme la acción específica realizada.
       ============================================================================================ */
    SELECT 
        CASE 
            WHEN _Nuevo_Estatus = 1 THEN CONCAT('ÉXITO: El Estatus "', v_Nombre_Actual, '" ha sido REACTIVADO y está disponible nuevamente en los selectores operativos.')
            ELSE CONCAT('ÉXITO: El Estatus "', v_Nombre_Actual, '" ha sido DESACTIVADO (Baja Lógica). Se mantendrá en el histórico pero no podrá seleccionarse en nuevos registros.')
        END AS Mensaje,
        'ESTATUS_CAMBIADO' AS Accion,
        v_Activo_Actual AS Estado_Anterior,
        _Nuevo_Estatus AS Estado_Nuevo,
        _Id_Estatus AS Id_Estatus_Participante;

END$$

DELIMITER ;