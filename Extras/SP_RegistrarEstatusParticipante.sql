/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarEstatusParticipante
   ====================================================================================================
   
   1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   ----------------------------------------------------------------------------------------------------
   Este procedimiento gestiona el ALTA TRANSACCIONAL de un "Estatus de Participante" en el catálogo
   maestro (`Cat_Estatus_Participante`).
   
   Su propósito es definir los posibles resultados finales de un asistente en un curso (ej: Aprobado, 
   Reprobado, No Asistió, Cancelado). Actúa como la **Puerta de Entrada Única** (Single Gateway) para 
   garantizar que no existan estados ambiguos que corrompan los reportes de cumplimiento normativo.

   2. REGLAS DE VALIDACIÓN ESTRICTA (HARD CONSTRAINTS)
   ---------------------------------------------------
   A) INTEGRIDAD DE DATOS (DATA HYGIENE):
      - Principio: "Datos limpios desde el origen".
      - Regla: El `Código` y el `Nombre` son obligatorios. No se permiten cadenas vacías o espacios.
      - Acción: Se aplica `TRIM` y validación `NOT NULL` antes de cualquier operación.

   B) IDENTIDAD UNÍVOCA DE DOBLE FACTOR (DUAL IDENTITY CHECK):
      - Unicidad por CÓDIGO: No pueden existir dos estatus con la clave 'APROB'.
      - Unicidad por NOMBRE: No pueden existir dos estatus llamados 'APROBADO'.
      - Resolución: Se verifica primero el Código (Identificador fuerte) y luego el Nombre.

   3. ESTRATEGIA DE PERSISTENCIA Y CONCURRENCIA (ACID & RACE CONDITIONS)
   ----------------------------------------------------------------------------------------------------
   A) BLOQUEO PESIMISTA (PESSIMISTIC LOCKING):
      - Se utiliza `SELECT ... FOR UPDATE` durante las verificaciones de existencia.
      - Justificación: Esto "serializa" las peticiones. Si dos administradores intentan crear el estatus
        "Oyente" al mismo tiempo, el segundo esperará a que el primero termine, evitando lecturas sucias.

   B) AUTOSANACIÓN (SELF-HEALING / SOFT DELETE RECOVERY):
      - Escenario: El estatus "Pendiente" existía, se dio de baja (`Activo=0`) y ahora se quiere volver a usar.
      - Acción: El sistema detecta el registro "muerto", lo reactiva (`Activo=1`), actualiza su descripción
        con la nueva información y lo devuelve como éxito. No se crea un duplicado físico.

   C) PATRÓN DE RECUPERACIÓN "RE-RESOLVE" (MANEJO DE ERROR 1062):
      - Escenario Crítico: Una "Condición de Carrera" donde dos usuarios hacen INSERT en el mismo microsegundo.
        El motor de BD frenará al segundo con error `1062 (Duplicate Entry)`.
      - Solución: Un `HANDLER` captura el error, hace rollback silencioso y ejecuta una búsqueda final
        para devolver el ID del registro que "ganó", garantizando una experiencia de usuario transparente.

   4. CONTRATO DE SALIDA (OUTPUT SPECIFICATION)
   --------------------------------------------
   Retorna un Resultset de fila única con:
      - [Mensaje]: Feedback descriptivo (ej: "Estatus registrado exitosamente").
      - [Id_Estatus_Participante]: La llave primaria del recurso.
      - [Accion]: Enumerador de estado ('CREADA', 'REACTIVADA', 'REUSADA').
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_RegistrarEstatusParticipante`$$

CREATE PROCEDURE `SP_RegistrarEstatusParticipante`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibimos los datos crudos del formulario.
       ----------------------------------------------------------------- */
    IN _Codigo      VARCHAR(50),   -- [OBLIGATORIO] Identificador corto (ej: 'APROB').
    IN _Nombre      VARCHAR(255),  -- [OBLIGATORIO] Nombre descriptivo (ej: 'APROBADO').
    IN _Descripcion VARCHAR(255)   -- [OPCIONAL] Detalles operativos (ej: 'Calif >= 8.0').
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: DECLARACIÓN DE VARIABLES DE ENTORNO
       Propósito: Inicializar contenedores para el estado de la base de datos.
       ======================================================================================== */
    
    /* Variables de Persistencia (Snapshot): Almacenan la "foto" del registro si ya existe */
    DECLARE v_Id_Estatus INT DEFAULT NULL;
    DECLARE v_Activo       TINYINT(1) DEFAULT NULL;
    
    /* Variables para Validación Cruzada (Cross-Check): Para detectar conflictos de identidad */
    DECLARE v_Nombre_Existente VARCHAR(255) DEFAULT NULL;
    DECLARE v_Codigo_Existente VARCHAR(50) DEFAULT NULL;
    
    /* Bandera de Control de Flujo (Semáforo): Indica si ocurrió un error SQL controlado (1062) */
    DECLARE v_Dup          TINYINT(1) DEFAULT 0;

    /* ========================================================================================
       BLOQUE 1: HANDLERS (MANEJO ROBUSTO DE EXCEPCIONES)
       Propósito: Asegurar la estabilidad del sistema ante fallos previstos e imprevistos.
       ======================================================================================== */
    
    /* 1.1 HANDLER DE DUPLICIDAD (Error 1062 - Duplicate Entry)
       Objetivo: Capturar colisiones de Unique Key en el INSERT final (la red de seguridad).
       Acción: No abortar. Encender bandera v_Dup = 1 para activar la rutina de recuperación. */
    DECLARE CONTINUE HANDLER FOR 1062 SET v_Dup = 1;

    /* 1.2 HANDLER GENÉRICO (SQLEXCEPTION)
       Objetivo: Capturar fallos técnicos (Disco lleno, Conexión perdida, Syntax Error).
       Acción: Abortar inmediatamente, deshacer cambios (ROLLBACK) y propagar el error. */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ========================================================================================
       BLOQUE 2: SANITIZACIÓN Y VALIDACIÓN PREVIA (FAIL FAST STRATEGY)
       Propósito: Rechazar datos inválidos antes de consumir recursos de transacción.
       ======================================================================================= */
    
    /* 2.1 LIMPIEZA DE DATOS (TRIM & NULLIF)
       Eliminamos espacios al inicio/final. Si la cadena queda vacía, la convertimos a NULL
       para facilitar la validación booleana estricta. */
    SET _Codigo      = NULLIF(TRIM(_Codigo), '');
    SET _Nombre      = NULLIF(TRIM(_Nombre), '');
    SET _Descripcion = NULLIF(TRIM(_Descripcion), '');

    /* 2.2 VALIDACIÓN DE OBLIGATORIEDAD (Business Rule: NO VACÍOS)
       Regla: Un Estatus sin Código o Nombre es una entidad corrupta inutilizable. */
    
    IF _Codigo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El CÓDIGO del Estatus es obligatorio.';
    END IF;

    IF _Nombre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE VALIDACIÓN [400]: El NOMBRE del Estatus es obligatorio.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: LÓGICA DE NEGOCIO TRANSACCIONAL (CORE)
       Propósito: Ejecutar la búsqueda, validación y persistencia de forma atómica.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: RESOLUCIÓN DE IDENTIDAD POR CÓDIGO (PRIORIDAD ALTA)
       
       Objetivo: Verificar si la clave única (_Codigo) ya está registrada en el sistema.
       Mecánica: Usamos `FOR UPDATE` para bloquear la fila encontrada.
       Justificación: Esto evita que otro usuario modifique o reactive este mismo registro
       mientras nosotros tomamos la decisión.
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Estatus = NULL; -- Reset de seguridad

    SELECT `Id_CatEstPart`, `Nombre`, `Activo` 
    INTO v_Id_Estatus, v_Nombre_Existente, v_Activo
    FROM `Cat_Estatus_Participante`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE; -- <--- BLOQUEO DE ESCRITURA AQUÍ

    /* ESCENARIO A: EL CÓDIGO YA EXISTE */
    IF v_Id_Estatus IS NOT NULL THEN
        
        /* A.1 Validación de Integridad Cruzada:
           Regla: Si el código existe, el Nombre TAMBIÉN debe coincidir.
           Fallo: Si el código es igual pero el nombre es diferente, es un CONFLICTO DE DATOS. */
        IF v_Nombre_Existente <> _Nombre THEN
            SIGNAL SQLSTATE '45000' 
                SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya existe pero pertenece a un Estatus con diferente NOMBRE. Verifique sus datos.';
        END IF;

        /* A.2 Sub-Escenario: Existe pero está INACTIVO (Baja Lógica) -> REACTIVAR (Autosanación)
           "Resucitamos" el registro y actualizamos su descripción si se proveyó una nueva. */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Participante` 
            SET `Activo` = 1, 
                /* Lógica de Fusión: Si el usuario mandó descripción nueva, la usamos. 
                   Si no, mantenemos la histórica (COALESCE). */
                `Descripcion` = COALESCE(_Descripcion, `Descripcion`), 
                `updated_at` = NOW() 
            WHERE `Id_CatEstPart` = v_Id_Estatus;
            
            COMMIT; 
            SELECT 'ÉXITO: Estatus reactivado y actualizado correctamente.' AS Mensaje, v_Id_Estatus AS Id_Estatus_Participante, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        
        /* A.3 Sub-Escenario: Existe y está ACTIVO -> IDEMPOTENCIA
           El registro ya está tal como lo queremos. No hacemos nada y reportamos éxito. */
        ELSE
            COMMIT; 
            SELECT 'AVISO: El Estatus ya se encuentra registrado y activo.' AS Mensaje, v_Id_Estatus AS Id_Estatus_Participante, 'REUSADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: RESOLUCIÓN DE IDENTIDAD POR NOMBRE (PRIORIDAD SECUNDARIA)
       
       Objetivo: Si llegamos aquí, el CÓDIGO es libre. Ahora verificamos si el NOMBRE ya está en uso.
       Esto previene que se creen duplicados semánticos con códigos diferentes (ej: 'APROBADO' vs 'APROBADO-1').
       ---------------------------------------------------------------------------------------- */
    SET v_Id_Estatus = NULL; -- Reset de seguridad

    SELECT `Id_CatEstPart`, `Codigo`, `Activo`
    INTO v_Id_Estatus, v_Codigo_Existente, v_Activo
    FROM `Cat_Estatus_Participante`
    WHERE `Nombre` = _Nombre
    LIMIT 1
    FOR UPDATE;

    /* ESCENARIO B: EL NOMBRE YA EXISTE */
    IF v_Id_Estatus IS NOT NULL THEN
        
        /* B.1 Conflicto de Identidad:
           El nombre existe, pero tiene asociado OTRO código diferente al que intentamos registrar. */
        IF v_Codigo_Existente IS NOT NULL AND v_Codigo_Existente <> _Codigo THEN
             SIGNAL SQLSTATE '45000' 
             SET MESSAGE_TEXT = 'CONFLICTO DE DATOS [409]: El NOMBRE ingresado ya existe pero está asociado a otro CÓDIGO diferente.';
        END IF;
        
        /* B.2 Caso Especial: Enriquecimiento de Datos (Data Enrichment)
           El registro existía con Código NULL (dato viejo), y ahora le estamos asignando un Código válido. */
        IF v_Codigo_Existente IS NULL THEN
             UPDATE `Cat_Estatus_Participante` 
             SET `Codigo` = _Codigo, `updated_at` = NOW() 
             WHERE `Id_CatEstPart` = v_Id_Estatus;
        END IF;

        /* B.3 Reactivación si estaba inactivo */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Participante` 
            SET `Activo` = 1, `Descripcion` = COALESCE(_Descripcion, `Descripcion`), `updated_at` = NOW() 
            WHERE `Id_CatEstPart` = v_Id_Estatus;
            
            COMMIT; 
            SELECT 'ÉXITO: Estatus reactivado correctamente (encontrado por Nombre).' AS Mensaje, v_Id_Estatus AS Id_Estatus_Participante, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;

        /* B.4 Idempotencia: Ya existe y está activo */
        COMMIT; 
        SELECT 'AVISO: El Estatus ya existe (validado por Nombre).' AS Mensaje, v_Id_Estatus AS Id_Estatus_Participante, 'REUSADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.3: PERSISTENCIA (INSERCIÓN FÍSICA)
       
       Si pasamos todas las validaciones y no encontramos coincidencias, es un registro NUEVO.
       Aquí existe un riesgo infinitesimal de "Race Condition" si otro usuario inserta 
       exactamente los mismos datos en este preciso instante (cubierto por Handler 1062).
       ---------------------------------------------------------------------------------------- */
    SET v_Dup = 0; -- Reiniciamos bandera de error
    
    INSERT INTO `Cat_Estatus_Participante`
    (
        `Codigo`, 
        `Nombre`, 
        `Descripcion`, 
        `Activo`,
        `created_at`,
        `updated_at`
    )
    VALUES
    (
        _Codigo, 
        _Nombre, 
        _Descripcion, 
        1,      -- Activo por defecto (Born Alive)
        NOW(),  -- Timestamp Creación
        NOW()   -- Timestamp Actualización
    );

    /* Verificación de Éxito: Si v_Dup sigue en 0, el INSERT fue limpio. */
    IF v_Dup = 0 THEN
        COMMIT; 
        SELECT 'ÉXITO: Estatus registrado correctamente.' AS Mensaje, LAST_INSERT_ID() AS Id_Estatus_Participante, 'CREADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* ========================================================================================
       BLOQUE 4: RUTINA DE RECUPERACIÓN DE CONCURRENCIA (RE-RESOLVE PATTERN)
       Propósito: Manejar elegantemente el Error 1062 (Duplicate Key) si ocurre una colisión.
       ======================================================================================== */
    
    /* Si estamos aquí, v_Dup = 1. Significa que "perdimos" la carrera contra otro INSERT. */
    
    ROLLBACK; -- 1. Revertir la transacción fallida para liberar bloqueos parciales.
    
    START TRANSACTION; -- 2. Iniciar una nueva transacción limpia.
    
    SET v_Id_Estatus = NULL;
    
    /* 3. Buscar el registro "ganador" (El que insertó el otro usuario).
       Intentamos recuperar por CÓDIGO (la restricción más fuerte). */
    SELECT `Id_CatEstPart`, `Activo`, `Nombre`
    INTO v_Id_Estatus, v_Activo, v_Nombre_Existente
    FROM `Cat_Estatus_Participante`
    WHERE `Codigo` = _Codigo
    LIMIT 1
    FOR UPDATE;
    
    IF v_Id_Estatus IS NOT NULL THEN
        /* Validación de Seguridad: Confirmar que no sea un falso positivo (nombre distinto) */
        IF v_Nombre_Existente <> _Nombre THEN
             SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO DE SISTEMA [500]: Concurrencia detectada con conflicto de datos (Códigos iguales, Nombres distintos).';
        END IF;

        /* Reactivación (si el ganador estaba inactivo) */
        IF v_Activo = 0 THEN
            UPDATE `Cat_Estatus_Participante` 
            SET `Activo` = 1, `Descripcion` = COALESCE(_Descripcion, `Descripcion`), `updated_at` = NOW() 
            WHERE `Id_CatEstPart` = v_Id_Estatus;
            
            COMMIT; 
            SELECT 'ÉXITO: Estatus reactivado (recuperado tras concurrencia).' AS Mensaje, v_Id_Estatus AS Id_Estatus_Participante, 'REACTIVADA' AS Accion; 
            LEAVE THIS_PROC;
        END IF;
        
        /* Éxito por Reuso (El ganador ya estaba activo) */
        COMMIT; 
        SELECT 'AVISO: El Estatus ya existía (reusado tras concurrencia).' AS Mensaje, v_Id_Estatus AS Id_Estatus_Participante, 'REUSADA' AS Accion; 
        LEAVE THIS_PROC;
    END IF;

    /* Fallo Irrecuperable: Si falló por 1062 pero no encontramos el registro 
       (Indica corrupción de índices o error fantasma grave) */
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [500]: Fallo de concurrencia no recuperable en Estatus de Participante.';

END$$

DELIMITER ;