DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_EditarCapacitacion`$$

CREATE PROCEDURE `SP_EditarCapacitacion`(
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
    IN _Id_Estatus          INT,       -- Nuevo Estado del flujo.

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
    IN _Asistentes_Reales   INT,       -- Ajuste manual del conteo de asistencia (si aplica).
    IN _Observaciones       TEXT       -- [CRÍTICO]: Justificación forense del cambio. Es OBLIGATORIA.
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
    -- NUEVA VARIABLE PARA GUARDAR EL CONTEO
    DECLARE v_Total_Movidos INT DEFAULT 0;
    
    /* --------------------------------------------------------------------------------------------
       HANDLER DE SEGURIDAD (FAIL-SAFE MECHANISM)
       En caso de cualquier error técnico, se ejecuta un ROLLBACK total.
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
    IF _Fecha_Inicio > _Fecha_Fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: Fechas inválidas. La fecha de inicio es posterior a la fecha de fin.';
    END IF;

    /* 0.3 Validación de Justificación (Forensic Compliance) */
    IF _Observaciones IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE AUDITORÍA [400]: La justificación (Observaciones) es obligatoria para realizar un cambio de versión.';
    END IF;

    /* ============================================================================================
       BLOQUE 1: VALIDACIÓN DE INTEGRIDAD ESTRUCTURAL (EL BLINDAJE)
       Objetivo: Evitar la corrupción del árbol genealógico del curso (Relación Padre-Hijo).
       ============================================================================================ */

    /* 1.1 Descubrimiento del Contexto (Parent & State Discovery) */
    SELECT `Fk_Id_Capacitacion`, `Activo` 
    INTO v_Id_Padre, v_Version_Es_Vigente
    FROM `DatosCapacitaciones` 
    WHERE `Id_DatosCap` = _Id_Version_Anterior 
    LIMIT 1;

    /* 1.2 Verificación de Existencia (404 Handling) */
    IF v_Id_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [404]: La versión que intenta editar no existe en los registros.';
    END IF;

    /* 1.3 Verificación de Vigencia (Concurrency Protection) */
    IF v_Version_Es_Vigente = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CONFLICTO DE INTEGRIDAD [409]: La versión que intenta editar YA NO ES VIGENTE. Alguien más modificó este curso recientemente.';
    END IF;

    /* ============================================================================================
       BLOQUE 2: VALIDACIÓN DE RECURSOS (ANTI-ZOMBIE RESOURCES CHECK)
       Objetivo: Asegurar que no se asignen recursos dados de baja.
       ============================================================================================ */
    
    /* 2.1 Verificación de Instructor */
    SELECT I.Activo INTO v_Es_Activo 
    FROM Usuarios U INNER JOIN Info_Personal I ON U.Fk_Id_InfoPersonal = I.Id_InfoPersonal 
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
        `Fk_Id_Capacitacion`, `Fk_Id_Instructor`, `Fk_Id_CatCases_Sedes`, `Fk_Id_CatModalCap`, 
        `Fk_Id_CatEstCap`, `Fecha_Inicio`, `Fecha_Fin`, `Observaciones`, `AsistentesReales`, 
        `Activo`, `Fk_Id_Usuario_DatosCap_Created_by`, `created_at`, `updated_at`
    ) VALUES (
        v_Id_Padre, _Id_Instructor, _Id_Sede, _Id_Modalidad, 
        _Id_Estatus, _Fecha_Inicio, _Fecha_Fin, _Observaciones, IFNULL(_Asistentes_Reales, 0), 
        1, _Id_Usuario_Editor, NOW(), NOW()
    );

    /* Captura crítica del ID generado para la migración de hijos */
    SET v_Nuevo_Id = LAST_INSERT_ID();

    /* --------------------------------------------------------------------------------------------
       PASO 3.2: ARCHIVADO DE LA VERSIÓN ANTERIOR (HISTORICAL ARCHIVING)
       Marcamos la versión origen como "Histórica" (Activo=0).
       -------------------------------------------------------------------------------------------- */
    UPDATE `DatosCapacitaciones` SET `Activo` = 0 WHERE `Id_DatosCap` = _Id_Version_Anterior;

    /* --------------------------------------------------------------------------------------------
       PASO 3.3: ACTUALIZACIÓN DE HUELLA EN EL PADRE (GLOBAL AUDIT TRAIL)
       -------------------------------------------------------------------------------------------- */
    UPDATE `Capacitaciones` 
    SET `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Editor, `updated_at` = NOW() 
    WHERE `Id_Capacitacion` = v_Id_Padre;

    /* ============================================================================================
       BLOQUE 4: MIGRACIÓN DE NIETOS (ESTRATEGIA: MOVER/RELINK) 🚀
       Objetivo: Preservar la integridad de los participantes SIN duplicar datos.
       Cambio de Lógica: En lugar de "Clonar" (INSERT), hacemos "Re-enlace" (UPDATE).
       ============================================================================================ */
    
    UPDATE `Capacitaciones_Participantes`
    SET 
        `Fk_Id_DatosCap` = v_Nuevo_Id,           -- Apuntamos a la NUEVA versión
        `updated_at` = NOW(),                    -- Registramos el momento del movimiento
        `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Editor -- Registramos quién autorizó el cambio
    WHERE `Fk_Id_DatosCap` = _Id_Version_Anterior;

	-- ¡FOTO INSTANTÁNEA! Guardamos el conteo ANTES del commit
    SET v_Total_Movidos = ROW_COUNT();
    
    /* ============================================================================================
       BLOQUE 5: COMMIT Y CONFIRMACIÓN
       Si llegamos aquí, la operación fue atómica y exitosa.
       ============================================================================================ */
    COMMIT;
    
    SELECT 
        v_Nuevo_Id AS `New_Id_Detalle`,
        'EXITO'    AS `Status_Message`,
        CONCAT('Versión actualizada exitosamente. Se movieron ', v_Total_Movidos, ' expedientes de alumnos a la nueva versión (Sin duplicados).') AS `Feedback`;

END$$

DELIMITER ;