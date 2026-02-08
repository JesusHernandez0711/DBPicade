DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_DictaminarInscripcion`$$

CREATE PROCEDURE `SP_DictaminarInscripcion`(
    IN _Id_CapPart      INT,            -- ID del registro (relación)
    IN _Nuevo_Estatus   INT,            -- Nuevo Estatus (Aceptado, Rechazado, Aprobado)
    IN _Calificacion    DECIMAL(5,2),   -- [OPCIONAL] Calificación Final (Si aplica)
    IN _Asistencia      DECIMAL(5,2)    -- [OPCIONAL] % Asistencia (Si aplica)
)
BEGIN
    DECLARE v_Existe INT;
    DECLARE v_Es_Final_Usuario TINYINT DEFAULT 0; -- Para saber si estamos cerrando el ciclo del alumno

    /* Validaciones */
    IF _Id_CapPart IS NULL OR _Nuevo_Estatus IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [400]: ID y Estatus son obligatorios.';
    END IF;

    START TRANSACTION;

    /* Verificar existencia y bloquear fila */
    SELECT 1 INTO v_Existe 
    FROM `Capacitaciones_Participantes` 
    WHERE `Id_CapPart` = _Id_CapPart 
    FOR UPDATE;

    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [404]: El registro de inscripción no existe.';
    END IF;

    /* Ejecutar Dictamen */
    /* Usamos COALESCE en Calificación/Asistencia para permitir actualizaciones parciales.
       Si envías NULL en _Calificacion, se mantiene el valor que ya tenía en la BD. */
    UPDATE `Capacitaciones_Participantes`
    SET 
        `Fk_Id_CatEstPart` = _Nuevo_Estatus,
        `Calificacion`     = COALESCE(_Calificacion, `Calificacion`),
        `PorcentajeAsistencia` = COALESCE(_Asistencia, `PorcentajeAsistencia`),
        `updated_at`       = NOW()
    WHERE `Id_CapPart` = _Id_CapPart;

    COMMIT;

    SELECT 'ÉXITO: El estatus del participante ha sido actualizado.' AS Mensaje,
           'DICTAMINADO' AS Accion,
           _Id_CapPart AS Id_CapPart;

END$$

DELIMITER ;