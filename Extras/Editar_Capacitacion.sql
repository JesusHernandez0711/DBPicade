/* ====================================================================================================
   PROCEDIMIENTO: SP_Editar_Capacitacion (ANTES SP_RegistrarMovimientoOperativo)
   ====================================================================================================
   
   1. FICHA TÉCNICA
   ----------------
   - Objetivo: Generar nueva versión (Hijo), Archivar anterior, Actualizar Padre y Migrar Nietos (Alumnos).
   - Nivel de Seguridad: PLATINUM (Validación de Concurrencia y Anti-Zombie).
   
   2. ESTRATEGIA ANTI-CORRUPCIÓN
   -----------------------------
   - Integridad del Padre: Se asegura que el Parent ID exista.
   - Integridad del Historial: Se verifica que la versión origen esté VIVA (Activo=1) antes de editarla.
   - Integridad de los Hijos: Se clona la matrícula tal cual está en la versión origen.

   3. MAPA DE ENTRADA (Sincronizado con UI)
   ------------------
   [0] Contexto, [1] Config, [2] Ejecución, [3] Resultados.
   ==================================================================================================== */
DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_Editar_Capacitacion`$$

CREATE PROCEDURE `SP_Editar_Capacitacion`(
    /* [GRUPO 0]: CONTEXTO TÉCNICO */
    IN _Id_Version_Anterior INT,       -- El ID de la versión que se está visualizando/editando
    IN _Id_Usuario_Editor   INT,       -- Usuario que firma el cambio

    /* [GRUPO 1]: CONFIGURACIÓN OPERATIVA (Lo que cambia de forma) */
    IN _Id_Instructor       INT,
    IN _Id_Sede             INT,
    IN _Id_Modalidad        INT,
    IN _Id_Estatus          INT,

    /* [GRUPO 2]: DATOS DE EJECUCIÓN (Lo que cambia de tiempo/razón) */
    IN _Fecha_Inicio        DATE,
    IN _Fecha_Fin           DATE,
    
    
    /* [GRUPO 3]: RESULTADOS (Lo que cambia de métrica) */
    IN _Asistentes_Reales   INT,        -- Conteo manual (opcional)
    
    IN _Observaciones       TEXT      -- Justificación OBLIGATORIA

)
THIS_PROC: BEGIN

    /* Variables de Entorno */
    DECLARE v_Id_Padre INT;            
    DECLARE v_Nuevo_Id INT;            
    DECLARE v_Es_Activo TINYINT(1);    
    DECLARE v_Version_Es_Vigente TINYINT(1);

    /* Handler de Seguridad: Rollback absoluto en caso de error técnico */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* ============================================================================================
       FASE 0: SANITIZACIÓN Y VALIDACIONES LÓGICAS
       ============================================================================================ */
    SET _Observaciones = NULLIF(TRIM(_Observaciones), '');

    /* 0.1 Validación Temporal */
    IF _Fecha_Inicio > _Fecha_Fin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [400]: Fechas inválidas. Inicio posterior a Fin.';
    END IF;

    /* 0.2 Validación de Justificación (Forensic Requirement) */
    IF _Observaciones IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [400]: La justificación (Observaciones) es obligatoria para auditar el cambio.';
    END IF;

    /* ============================================================================================
       FASE 1: VALIDACIÓN DE INTEGRIDAD ESTRUCTURAL (EL BLINDAJE)
       Aquí evitamos que se corrompa la relación Padre-Hijo o el Historial.
       ============================================================================================ */

    /* 1.1 Descubrimiento del Padre y Verificación de Estado de la Versión Anterior */
    SELECT `Fk_Id_Capacitacion`, `Activo` 
    INTO v_Id_Padre, v_Version_Es_Vigente
    FROM `DatosCapacitaciones` 
    WHERE `Id_DatosCap` = _Id_Version_Anterior 
    LIMIT 1;

    /* A) ¿Existe la versión origen? */
    IF v_Id_Padre IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR CRÍTICO [404]: La versión que intenta editar no existe. Refresque su navegador.';
    END IF;

    /* B) ¿La versión origen sigue VIVA? (Protección contra Concurrencia y Corrupción de Historial) */
    /* Si Activo es 0, significa que alguien más ya editó o archivó esta versión. No podemos editar un cadáver. */
    IF v_Version_Es_Vigente = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE INTEGRIDAD [409]: La versión que intenta editar YA NO ES VIGENTE. Alguien más modificó el curso recientemente. Por favor actualice la página.';
    END IF;

    /* ============================================================================================
       FASE 2: VALIDACIÓN ANTI-ZOMBIE (Recursos Vivos)
       No permitimos asignar recursos dados de baja.
       ============================================================================================ */
    
    /* Instructor */
    SELECT I.Activo INTO v_Es_Activo FROM Usuarios U INNER JOIN Info_Personal I ON U.Fk_Id_InfoPersonal = I.Id_InfoPersonal WHERE U.Id_Usuario = _Id_Instructor LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [409]: El Instructor seleccionado está inactivo o dado de baja.'; END IF;

    /* Sede */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Cases_Sedes` WHERE `Id_CatCases_Sedes` = _Id_Sede LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [409]: La Sede seleccionada está clausurada o inactiva.'; END IF;

    /* Modalidad */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Modalidad_Capacitacion` WHERE `Id_CatModalCap` = _Id_Modalidad LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [409]: La Modalidad seleccionada no es válida actualmente.'; END IF;

    /* Estatus */
    SELECT `Activo` INTO v_Es_Activo FROM `Cat_Estatus_Capacitacion` WHERE `Id_CatEstCap` = _Id_Estatus LIMIT 1;
    IF v_Es_Activo IS NULL OR v_Es_Activo = 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [409]: El Estatus seleccionado está obsoleto.'; END IF;


    /* ============================================================================================
       FASE 3: TRANSACCIÓN DE VERSIONADO (ESCRITURA)
       ============================================================================================ */
    START TRANSACTION;

    /* 3.1 Insertar Nueva Versión (Hijo) */
    /* Nace vinculada al Mismo Padre (v_Id_Padre) para mantener la agrupación del expediente */
    INSERT INTO `DatosCapacitaciones` (
        `Fk_Id_Capacitacion`, 
        `Fk_Id_Instructor`, `Fk_Id_CatCases_Sedes`, `Fk_Id_CatModalCap`, `Fk_Id_CatEstCap`, 
        `Fecha_Inicio`, `Fecha_Fin`, `Observaciones`, `AsistentesReales`, 
        `Activo`, 
        `Fk_Id_Usuario_DatosCap_Created_by`, -- El editor se convierte en el AUTOR de esta versión
        `created_at`, `updated_at`
    ) VALUES (
        v_Id_Padre,          
        _Id_Instructor, _Id_Sede, _Id_Modalidad, _Id_Estatus,         
        _Fecha_Inicio, _Fecha_Fin, _Observaciones, IFNULL(_Asistentes_Reales, 0), 
        1,                   -- Esta nueva versión asume el mando (Activo=1)
        _Id_Usuario_Editor,  
        NOW(), NOW()
    );

    SET v_Nuevo_Id = LAST_INSERT_ID();

    /* 3.2 Archivar Versión Anterior (Histórico) */
    /* Esto garantiza que solo haya UN registro activo por Padre en un momento dado */
    UPDATE `DatosCapacitaciones` 
    SET `Activo` = 0 
    WHERE `Id_DatosCap` = _Id_Version_Anterior;

    /* 3.3 Actualizar Huella en el Padre (Auditoría Global) */
    /* El expediente (carpeta) debe saber que fue modificado hoy */
    UPDATE `Capacitaciones`
    SET 
        `Fk_Id_Usuario_Cap_Updated_by` = _Id_Usuario_Editor,
        `updated_at` = NOW()
    WHERE `Id_Capacitacion` = v_Id_Padre;

    /* ============================================================================================
       FASE 4: MIGRACIÓN DE NIETOS (MATRÍCULA DE ALUMNOS)
       Evitamos corrupción de relaciones: Los alumnos deben "moverse" a la nueva versión.
       Usamos INSERT SELECT para clonar.
       ============================================================================================ */
    
    INSERT INTO `Capacitaciones_Participantes` (
        `Fk_Id_DatosCap`,            -- DESTINO: El nuevo ID de versión
        `Fk_Id_Usuario`,             -- Mismo Alumno
        `Fk_Id_CatEstPart`,          -- Mismo Estatus (Aprobado, etc)
        `PorcentajeAsistencia`,      -- Misma Asistencia
        `Calificacion`,              -- Misma Calificación
        `created_at`,                -- Nuevo timestamp de registro en esta versión
        `updated_at`
    )
    SELECT 
        v_Nuevo_Id,                  
        `Fk_Id_Usuario`, `Fk_Id_CatEstPart`, `PorcentajeAsistencia`, `Calificacion`, 
        NOW(), NOW()
    FROM `Capacitaciones_Participantes`
    WHERE `Fk_Id_DatosCap` = _Id_Version_Anterior; -- ORIGEN: La versión que acabamos de archivar

    /* ============================================================================================
       FASE 5: CONFIRMACIÓN
       ============================================================================================ */
    COMMIT;

    SELECT 
        v_Nuevo_Id AS `New_Id_Detalle`,
        'EXITO'    AS `Status_Message`,
        'Capacitación editada correctamente. Historial generado.' AS `Feedback`;

END$$

DELIMITER ;