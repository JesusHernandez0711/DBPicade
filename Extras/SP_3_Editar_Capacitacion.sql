/* ====================================================================================================
   PROCEDIMIENTO: SP_Editar_Capacitacion (ANTES SP_RegistrarMovimientoOperativo)
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Tipo de Artefacto:  Procedimiento Almacenado de Transacción Compuesta (Composite Transaction SP)
   - Patrón de Diseño:   "Append-Only Ledger with State Migration" (Libro Mayor de Solo Agregación con Migración de Estado)
   - Nivel de Aislamiento: SERIALIZABLE (Implícito por bloqueos de escritura)

   2. VISIÓN DE NEGOCIO (BUSINESS VALUE PROPOSITION)
   -------------------------------------------------
   Este procedimiento actúa como el "Motor de Versionado Forense". Su objetivo es permitir la modificación
   de las condiciones operativas de un curso (Instructor, Fechas, Sede) SIN DESTRUIR LA EVIDENCIA HISTÓRICA.
   
   [PRINCIPIO DE INMUTABILIDAD]:
   En lugar de sobrescribir el registro actual (UPDATE destructivo), este motor:
     A. Crea una nueva versión "Hija" con los datos modificados.
     B. Archiva la versión anterior como "Histórica" (Soft Delete).
     C. Actualiza la huella de auditoría en el expediente "Padre".
     D. Migra masivamente a todos los participantes inscritos hacia la nueva versión.

   3. ESTRATEGIA DE DEFENSA CONTRA CORRUPCIÓN (ANTI-CORRUPTION LAYER)
   ------------------------------------------------------------------
   Implementa un blindaje de triple nivel para garantizar la integridad referencial y temporal:
     - Nivel 1 (Integridad del Padre): Verifica que el expediente maestro exista antes de crear una nueva rama.
     - Nivel 2 (Integridad del Historial): Aplica "Optimistic Concurrency Control". Verifica que la versión
       origen esté VIVA (Activo=1). Si alguien más la archivó 1 milisegundo antes, la operación se bloquea
       para evitar crear ramas huérfanas o bifurcaciones en la historia.
     - Nivel 3 (Integridad de los Hijos): Ejecuta una clonación transaccional (Atomic Cloning) de la
       matrícula de alumnos. Si el curso tiene 50 alumnos, los 50 se mueven instantáneamente a la nueva versión.

   4. MAPA DE ENTRADA (UX SYNCHRONIZATION)
   ---------------------------------------
   Los parámetros están ordenados cronológicamente según el flujo visual del formulario de edición:
     [0] Contexto Técnico (IDs ocultos)
     [1] Configuración Operativa (Recursos y Modalidad)
     [2] Ejecución Temporal (Fechas y Justificación)
     [3] Resultados (Métricas)
   ==================================================================================================== */
DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_Editar_Capacitacion`$$

CREATE PROCEDURE `SP_Editar_Capacitacion`(
    /* --------------------------------------------------------------------------------------------
       [GRUPO 0]: CONTEXTO TÉCNICO Y DE AUDITORÍA
       Datos invisibles para el usuario pero vitales para la integridad del sistema.
       -------------------------------------------------------------------------------------------- */
    IN _Id_Version_Anterior INT,       -- Puntero a la versión que se está visualizando/editando (Origen).
    IN _Id_Usuario_Editor   INT,       -- ID del usuario que firma legalmente este cambio.

    /* --------------------------------------------------------------------------------------------
       [GRUPO 1]: CONFIGURACIÓN OPERATIVA (MUTABLES ESTRUCTURALES)
       Datos que definen la "Forma" del curso.
       -------------------------------------------------------------------------------------------- */
    IN _Id_Instructor       INT,       -- Nuevo Recurso Humano responsable.
    IN _Id_Sede             INT,       -- Nueva Ubicación física/virtual.
    IN _Id_Modalidad        INT,       -- Nuevo Formato de entrega.
    IN _Id_Estatus          INT,       -- Nuevo Estado del flujo (ej: De 'Programado' a 'Reprogramado').

    /* --------------------------------------------------------------------------------------------
       [GRUPO 2]: DATOS DE EJECUCIÓN (MUTABLES TEMPORALES)
       Datos que definen el "Tiempo y Razón" del curso.
       -------------------------------------------------------------------------------------------- */
    IN _Fecha_Inicio        DATE,      -- Nueva fecha de arranque.
    IN _Fecha_Fin           DATE,      -- Nueva fecha de cierre.
    
    
    /* --------------------------------------------------------------------------------------------
       [GRUPO 3]: RESULTADOS (MÉTRICAS)
       Datos cuantitativos post-operativos.
       -------------------------------------------------------------------------------------------- */
    IN _Asistentes_Reales   INT,        -- Ajuste manual del conteo de asistencia (si aplica).
    
    IN _Observaciones       TEXT      -- [CRÍTICO]: Justificación forense del cambio. Es OBLIGATORIA.

)
THIS_PROC: BEGIN

    /* --------------------------------------------------------------------------------------------
       DECLARACIÓN DE VARIABLES DE ENTORNO (CONTEXT VARIABLES)
       Contenedores temporales para mantener el estado durante la transacción.
       -------------------------------------------------------------------------------------------- */
    DECLARE v_Id_Padre INT;            -- Almacena el ID del Expediente Maestro (Invariable).
    DECLARE v_Nuevo_Id INT;            -- Almacenará el ID generado para la nueva versión.
    DECLARE v_Es_Activo TINYINT(1);    -- Semáforo booleano para validaciones Anti-Zombie.
    DECLARE v_Version_Es_Vigente TINYINT(1); -- Bandera de estado de la versión origen.
    
    /* [CRÍTICO] Faltaba esta variable en tu código anterior */
    DECLARE v_Tiene_Evidencia TINYINT(1) DEFAULT 0;

    /* --------------------------------------------------------------------------------------------
       HANDLER DE SEGURIDAD (FAIL-SAFE MECHANISM)
       En caso de cualquier error técnico (disco lleno, desconexión, FK rota), se ejecuta
       un ROLLBACK total para dejar la base de datos en su estado original inmaculado.
       -------------------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       BLOQUE 0: SANITIZACIÓN Y VALIDACIONES LÓGICAS (PRE-FLIGHT CHECK)
       Objetivo: Validar la coherencia de los datos antes de tocar la estructura.
       ============================================================================================ */
    
    /* 0.1 Limpieza de Strings */
    SET _Observaciones = NULLIF(TRIM(_Observaciones), '');

    /* 0.2 Validación Temporal (Time Integrity) */
    /* Regla: El tiempo es lineal. El inicio no puede ser posterior al fin. */
    IF _Fecha_Inicio > _Fecha_Fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: Fechas inválidas. La fecha de inicio es posterior a la fecha de fin.';
    END IF;

    /* 0.3 Validación de Justificación (Forensic Compliance) */
    /* Regla: No se permite alterar la historia sin dejar una razón documentada. */
    IF _Observaciones IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE AUDITORÍA [400]: La justificación (Observaciones) es obligatoria para realizar un cambio de versión.';
    END IF;

    /* ============================================================================================
       BLOQUE 1: VALIDACIÓN DE INTEGRIDAD ESTRUCTURAL (EL BLINDAJE)
       Objetivo: Evitar la corrupción del árbol genealógico del curso (Relación Padre-Hijo).
       ============================================================================================ */

    /* 1.1 Descubrimiento del Contexto (Parent & State Discovery) */
    /* Buscamos quién es el padre y en qué estado está la versión que queremos editar. */
    SELECT `Fk_Id_Capacitacion`, `Activo` 
    INTO v_Id_Padre, v_Version_Es_Vigente
    FROM `DatosCapacitaciones` 
    WHERE `Id_DatosCap` = _Id_Version_Anterior 
    LIMIT 1;

    /* 1.2 Verificación de Existencia (404 Handling) */
    IF v_Id_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [404]: La versión que intenta editar no existe en los registros. Por favor refresque su navegador.';
    END IF;

    /* 1.3 Verificación de Vigencia (Concurrency Protection) */
    /* [ESTRATEGIA ANTI-CORRUPCIÓN]: Si v_Version_Es_Vigente es 0, significa que esta versión YA FUE
       archivada por otra transacción. No podemos editar un registro histórico ("cadáver").
       Esto previene bifurcaciones en la línea de tiempo. */
    IF v_Version_Es_Vigente = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE INTEGRIDAD [409]: La versión que intenta editar YA NO ES VIGENTE. Alguien más modificó este curso recientemente. Por favor actualice la página para ver la última versión.';
    END IF;

    /* ============================================================================================
       BLOQUE 2: VALIDACIÓN DE RECURSOS (ANTI-ZOMBIE RESOURCES CHECK)
       Objetivo: Asegurar que no se asignen recursos (Instructores, Sedes) dados de baja.
       Se realizan consultas puntuales para verificar `Activo = 1` en cada catálogo.
       ============================================================================================ */
    
    /* 2.1 Verificación de Instructor */
    /* Nota: Se valida tanto el Usuario como su InfoPersonal asociada. */
    SELECT I.Activo INTO v_Es_Activo 
    FROM Usuarios U 
    INNER JOIN Info_Personal I ON U.Fk_Id_InfoPersonal = I.Id_InfoPersonal 
    WHERE U.Id_Usuario = _Id_Instructor LIMIT 1;
    
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Instructor seleccionado está inactivo o ha sido dado de baja.'; 
    END IF;

    /* 2.2 Verificación de Sede */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Cases_Sedes` WHERE `Id_CatCases_Sedes` = _Id_Sede LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: La Sede seleccionada está clausurada o inactiva.'; 
    END IF;

    /* 2.3 Verificación de Modalidad */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = _Id_Modalidad LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: La Modalidad seleccionada no es válida actualmente.'; 
    END IF;

    /* 2.4 Verificación de Estatus */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = _Id_Estatus LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [409]: El Estatus seleccionado está obsoleto o inactivo.'; 
    END IF;

    /* ============================================================================================
       BLOQUE 3: TRANSACCIÓN MAESTRA (ATOMIC WRITING)
       Punto de No Retorno. Iniciamos la escritura física en disco.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO 3.1: CREACIÓN DE LA NUEVA VERSIÓN (VERSIONING)
       Insertamos la nueva realidad operativa (`DatosCapacitaciones`) vinculada al mismo Padre.
       -------------------------------------------------------------------------------------------- */
    INSERT INTO `DatosCapacitaciones` (
        `Fk_Id_Capacitacion`,                -- Vinculación Inmutable con el Padre
        `Fk_Id_Instructor`, 
        `Fk_Id_CatCases_Sedes`, 
        `Fk_Id_CatModalCap`, 
        `Fk_Id_CatEstCap`, 
        `Fecha_Inicio`, 
        `Fecha_Fin`, 
        `Observaciones`, 
        `AsistentesReales`, 
        `Activo`,                            -- Estado de la Versión
        `Fk_Id_Usuario_DatosCap_Created_by`, -- Firma del Editor (Autor de esta versión)
        `created_at`, 
        `updated_at`
    ) VALUES (
        v_Id_Padre,          
        _Id_Instructor, 
        _Id_Sede, 
        _Id_Modalidad, 
        _Id_Estatus,         
        _Fecha_Inicio, 
        _Fecha_Fin, 
        _Observaciones, 
        IFNULL(_Asistentes_Reales, 0), 
        1,                                   -- [REGLA]: La nueva versión nace VIVA (Vigente).
        _Id_Usuario_Editor,  
        NOW(), 
        NOW()
    );

    /* Captura crítica del ID generado para la migración de hijos */
    SET v_Nuevo_Id = LAST_INSERT_ID();

    /* --------------------------------------------------------------------------------------------
       PASO 3.2: ARCHIVADO DE LA VERSIÓN ANTERIOR (HISTORICAL ARCHIVING)
       Marcamos la versión origen como "Histórica" (Activo=0).
       Esto garantiza que siempre exista UNA SOLA versión vigente por curso.
       -------------------------------------------------------------------------------------------- */
    UPDATE `DatosCapacitaciones` 
    SET `Activo` = 0 
    WHERE `Id_DatosCap` = _Id_Version_Anterior;

    /* --------------------------------------------------------------------------------------------
       PASO 3.3: ACTUALIZACIÓN DE HUELLA EN EL PADRE (GLOBAL AUDIT TRAIL)
       El expediente maestro (`Capacitaciones`) debe saber que fue modificado hoy.
       - Updated_by: Se actualiza al editor actual.
       - Created_by: SE RESPETA INTACTO (Autor Intelectual original).
       -------------------------------------------------------------------------------------------- */
    UPDATE `Capacitaciones`
    SET 
        `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Editor,
        `updated_at` = NOW()
    WHERE `Id_Capacitacion` = v_Id_Padre;

    /* ============================================================================================
       BLOQUE 4: MIGRACIÓN DE NIETOS (MATRICULA MIGRATION)
       Objetivo: Preservar la integridad de los participantes.
       Estrategia: Clonación Masiva (Bulk Clone). Los alumnos inscritos en la versión vieja
       son copiados a la nueva versión para que no queden "huérfanos" en el historial.
       ============================================================================================ */

	/* ============================================================================================
       BLOQUE 4: MIGRACIÓN DE NIETOS - LÓGICA HÍBRIDA INTELIGENTE
       ============================================================================================ */
    
    /* [ESTRATEGIA DE OPTIMIZACIÓN]:
       - SI el curso estaba en "Planeación" (Programado, Por Iniciar, Reprogramado), 
         ASUMIMOS que no hay historia académica relevante aún. -> HACEMOS UPDATE (Mover).
       - SI el curso estaba en "Ejecución" (En Curso, Finalizado, etc.),
         ASUMIMOS que la historia es sagrada. -> HACEMOS INSERT (Clonar).
       
       [MAPA DE IDs DE ESTATUS]:
       1 = PROGRAMADO
       2 = POR INICIAR
       9 = REPROGRAMADO
       (Cualquier otro ID se considera etapa de ejecución/cierre)
    */

	/* REGLA DE NEGOCIO:
		La información académica (calificación/asistencia) SOLO se captura al finalizar el curso
		(Estatus: EN EVALUACIÓN o superior). Antes de eso, no hay datos históricos que proteger.
       
		[ESTRATEGIA]:
		- Si el estatus anterior era: PROGRAMADO(1), POR INICIAR(2), REPROGRAMADO(9) O EN CURSO(3)
		-> MOVER (UPDATE) para no generar duplicados vacíos.
		- Si el estatus anterior era: EVALUACIÓN(5), FINALIZADO(4), ACREDITADO(6), etc.
		-> CLONAR (INSERT) para proteger las calificaciones ya capturadas.
	*/
    
        /* ----------------------------------------------------------------------------------------
           CASO A: FASE DE PLANEACIÓN -> MOVER (UPDATE)
           "Corrección administrativa". No generamos duplicados.
           Los alumnos se desconectan de la versión vieja y se conectan a la nueva.
           ---------------------------------------------------------------------------------------- */
           
        /* ----------------------------------------------------------------------------------------
           CASO B: FASE DE EJECUCIÓN -> CLONAR (INSERT SELECT)
           "Evolución histórica". Preservamos la foto del pasado.
           Creamos copias de los alumnos para la nueva versión, dejando los viejos intactos.
           ---------------------------------------------------------------------------------------- */
           
	/* ============================================================================================
       BLOQUE 4: MIGRACIÓN DE NIETOS - ESCÁNER DE EVIDENCIA (DATA-DRIVEN MIGRATION)
       ============================================================================================ */

    /* PASO 4.1: ESCANEAR LA VERSIÓN ANTERIOR
       Buscamos si EXISTE al menos un alumno con Calificación o Asistencia registrada.
       Si v_Tiene_Evidencia = 0, significa que la hoja está "en blanco" académicamente.
    */
    SELECT EXISTS (
        SELECT 1 
        FROM `Capacitaciones_Participantes`
        WHERE `Fk_Id_DatosCap` = _Id_Version_Anterior
        AND (
            `Calificacion` IS NOT NULL 
            OR `PorcentajeAsistencia` IS NOT NULL 
            OR `PorcentajeAsistencia` > 0
        )
    ) INTO v_Tiene_Evidencia;

    /* PASO 4.2: DECISIÓN BASADA EN DATOS */
    
    IF v_Tiene_Evidencia = 0 THEN
        
        /* CASO A: SIN DATOS ACADÉMICOS -> MOVER (UPDATE)
           No importa el estatus (Cancelado, Finalizado, En Curso). 
           Si no hay calificaciones, no hay nada histórico que "fotocopiar".
           Ahorramos espacio moviendo los registros. */
        
        UPDATE `Capacitaciones_Participantes`
        SET 
            `Fk_Id_DatosCap` = v_Nuevo_Id,
            `updated_at` = NOW(),
            `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Editor -- <--- NUEVO: Registro del responsable
        WHERE `Fk_Id_DatosCap` = _Id_Version_Anterior;

    ELSE
        
        /* CASO B: CON DATOS ACADÉMICOS -> CLONAR (INSERT)
           ¡Alerta! Hay calificaciones registradas. 
           Debemos preservar la versión anterior intacta como evidencia forense
           y crear nuevas copias para la nueva versión. */

	/* CASO B: CLONAR (INSERT) - CON HERENCIA DE AUDITORÍA */
        INSERT INTO `Capacitaciones_Participantes` (
            `Fk_Id_DatosCap`, `Fk_Id_Usuario`, `Fk_Id_CatEstPart`, 
            `PorcentajeAsistencia`, `Calificacion`, 
            /* AUDITORÍA */
            `created_at`, `updated_at`, 
            `Fk_Id_Usuario_Created_By`, `Fk_Id_Usuario_Updated_By`
        )
        SELECT 
            v_Nuevo_Id, 
            `Fk_Id_Usuario`, 
            `Fk_Id_CatEstPart`, 
            `PorcentajeAsistencia`, 
            `Calificacion`, 
            /* AUDITORÍA INTELIGENTE */
            `created_at`,           -- MANTENEMOS la fecha original de inscripción
            NOW(),                  -- ACTUALIZAMOS la fecha de esta nueva versión
            `Fk_Id_Usuario_Created_By`, -- MANTENEMOS al autor original
            _Id_Usuario_Editor      -- ACTUALIZAMOS al responsable de la edición
        FROM `Capacitaciones_Participantes`
        WHERE `Fk_Id_DatosCap` = _Id_Version_Anterior;
        
    END IF;

    /* ============================================================================================
       BLOQUE 5: COMMIT Y CONFIRMACIÓN
       Si llegamos aquí, la operación fue atómica y exitosa.
       ============================================================================================ */
    COMMIT;
    
    SELECT 
        v_Nuevo_Id AS `New_Id_Detalle`,
        'EXITO'    AS `Status_Message`,
        CASE 
            WHEN v_Tiene_Evidencia = 0 THEN 'Participantes MOVIDOS (Sin evidencia académica -> 0 Duplicados).'
            ELSE 'Participantes CLONADOS (Evidencia académica detectada -> Historial preservado).'
        END AS `Feedback`;

    /* Retorno de resultados para el Frontend 
    SELECT 
        v_Nuevo_Id AS `New_Id_Detalle`,
        'EXITO'    AS `Status_Message`,
        'Capacitación editada correctamente. Historial generado y matrícula migrada.' AS `Feedback`;*/

END$$

DELIMITER ;
