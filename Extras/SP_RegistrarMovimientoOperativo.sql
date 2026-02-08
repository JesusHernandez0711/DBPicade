USE Picade;

/* ====================================================================================================
   PROCEDIMIENTO: SP_RegistrarMovimientoOperativo (EDITAR CAPACITACIÓN)
   ====================================================================================================
   
   1. FICHA TÉCNICA
   ----------------
   - Nombre: SP_RegistrarMovimientoOperativo
   - Tipo: Transacción de Versionado y Migración (Versioning & Migration Transaction)
   - Objetivo: Actualizar un curso SIN SOBRESCRIBIR la historia, y asegurando que los alumnos
     se muevan a la nueva versión automáticamente.
   
   2. LÓGICA DE NEGOCIO "IMMUTABLE LEDGER"
   ---------------------------------------
   En lugar de hacer `UPDATE DatosCapacitaciones SET...`, hacemos un `INSERT` nuevo.
   Esto preserva la versión anterior como evidencia forense.
   
   3. LÓGICA DE "MIGRACIÓN DE MATRÍCULA" (TU REQUERIMIENTO CLAVE)
   --------------------------------------------------------------
   Utiliza un `INSERT INTO ... SELECT` para copiar masivamente a los participantes.
   Si tenías 50 alumnos en la versión vieja, la nueva versión nace con esos mismos 50 alumnos.
   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_RegistrarMovimientoOperativo`$$

CREATE PROCEDURE `SP_RegistrarMovimientoOperativo`(
    /* --- CONTEXTO DE TRAZABILIDAD --- */
    IN _Id_Version_Anterior INT,       -- ID de la versión que se está editando (Origen)
    IN _Id_Usuario_Editor   INT,       -- Usuario que realiza el cambio (Auditoría)

    /* --- NUEVOS DATOS OPERATIVOS (PAYLOAD) --- */
    IN _Id_Instructor       INT,
    IN _Fecha_Inicio        DATE,
    IN _Fecha_Fin           DATE,
    IN _Id_Sede             INT,
    IN _Id_Modalidad        INT,
    IN _Id_Estatus          INT,       -- Nuevo estatus (ej: Reprogramado)
    IN _Observaciones       TEXT,      -- Justificación del cambio
    IN _Asistentes_Reales   INT        -- Actualización del conteo manual (si aplica)
)
THIS_PROC: BEGIN

    /* Variables Locales */
    DECLARE v_Id_Padre INT;         -- El ID de la Carpeta Maestra (Capacitaciones)
    DECLARE v_Nuevo_Id INT;         -- El ID de la nueva versión que vamos a crear
    
    /* Manejo de Errores */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       FASE 0: PROGRAMACIÓN DEFENSIVA Y VALIDACIONES
       ============================================================================================ */
    
    /* 0.1 Limpieza */
    SET _Observaciones = NULLIF(TRIM(_Observaciones), '');

    /* 0.2 Validación Temporal */
    IF _Fecha_Inicio > _Fecha_Fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: La Fecha de Inicio no puede ser posterior a la Fecha de Fin.';
    END IF;

    /* 0.3 Recuperación del Padre (Parent Discovery) */
    SELECT `Fk_Id_Capacitacion` INTO v_Id_Padre
    FROM `DatosCapacitaciones`
    WHERE `Id_DatosCap` = _Id_Version_Anterior
    LIMIT 1;

    /* 0.4 Validación de Existencia */
    IF v_Id_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [404]: La versión que intenta editar ya no existe.';
    END IF;

    /* ============================================================================================
       FASE 1: INICIO DE TRANSACCIÓN ATÓMICA
       ============================================================================================ */
    START TRANSACTION;

    /* ============================================================================================
       FASE 2: CREACIÓN DE LA NUEVA VERSIÓN (VERSIONING)
       Insertamos la nueva realidad operativa vinculada al mismo Padre.
       ============================================================================================ */
    INSERT INTO `DatosCapacitaciones` (
        `Fk_Id_Capacitacion`, 
        `Fk_Id_Instructor`, 
        `Fecha_Inicio`, 
        `Fecha_Fin`, 
        `Fk_Id_CatCases_Sedes`, 
        `Fk_Id_CatModalCap`, 
        `Fk_Id_CatEstCap`, 
        `AsistentesReales`, 
        `Observaciones`, 
        `Activo`, 
        `Fk_Id_Usuario_DatosCap_Created_by`, 
        `created_at`,
        `updated_at`
    ) VALUES (
        v_Id_Padre,             -- Mismo Padre
        _Id_Instructor,         -- Nuevo Instructor
        _Fecha_Inicio,          -- Nuevas Fechas
        _Fecha_Fin, 
        _Id_Sede, 
        _Id_Modalidad, 
        _Id_Estatus, 
        IFNULL(_Asistentes_Reales, 0), 
        _Observaciones, 
        1,                      -- La nueva versión nace ACTIVA (Vigente)
        _Id_Usuario_Editor,     -- Firmado por quien edita
        NOW(),
        NOW()
    );

    /* Capturamos el ID del nuevo registro (ej: 501) */
    SET v_Nuevo_Id = LAST_INSERT_ID();

    /* ============================================================================================
       FASE 3: DESACTIVACIÓN DE LA VERSIÓN ANTERIOR (SOFT DELETE)
       Marcamos la versión vieja (ej: 500) como histórica (Activo=0).
       ============================================================================================ */
    UPDATE `DatosCapacitaciones` 
    SET `Activo` = 0 
    WHERE `Id_DatosCap` = _Id_Version_Anterior;

    /* ============================================================================================
       FASE 4: MIGRACIÓN DE PARTICIPANTES (CLONACIÓN MASIVA)
       Copiamos a los alumnos de la versión vieja a la nueva.
       ============================================================================================ */
    INSERT INTO `Registro_Participantes` (
        `Fk_Id_DatosCap`,            -- Aquí va el NUEVO ID (ej: 501)
        `Fk_Id_Usuario`,             -- El ID del alumno
        `Asistencia`,                -- Hereda asistencia
        `Calificacion`,              -- Hereda calificación
        `Fk_Id_Estatus_Participante`,-- Hereda estatus (Aprobado, Inscrito)
        `Activo`,
        `created_at`,
        `updated_at`
    )
    SELECT 
        v_Nuevo_Id,                  -- <-- DESTINO: La nueva versión
        `Fk_Id_Usuario`,
        `Asistencia`,
        `Calificacion`,
        `Fk_Id_Estatus_Participante`,
        1,                           -- Nacen activos en la nueva versión
        NOW(),
        NOW()
    FROM `Registro_Participantes`
    WHERE `Fk_Id_DatosCap` = _Id_Version_Anterior -- <-- ORIGEN: La versión vieja
      AND `Activo` = 1;                           -- Solo alumnos activos

    /* ============================================================================================
       FASE 5: COMMIT Y CONFIRMACIÓN
       ============================================================================================ */
    COMMIT;

    SELECT 
        v_Nuevo_Id AS `New_Id_Detalle`,
        'EXITO'    AS `Status_Message`,
        'El curso ha sido actualizado y los participantes han sido migrados a la nueva versión.' AS `User_Feedback`;

END$$

DELIMITER ;