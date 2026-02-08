
/* ======================================================================================================
   PROCEDIMIENTO 2: SP_Dar_Baja_Participante
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Cambiar el estatus de un participante a BAJA, liberando su cupo para otro usuario.
   
   REGLAS DE NEGOCIO:
   ------------------
   1. El registro de participante debe existir.
   2. El participante no debe estar ya dado de BAJA.
   3. No se puede dar de baja si ya tiene calificación registrada (curso en evaluación/finalizado).
   4. El cambio a BAJA libera el asiento para otro participante.
   
   PARÁMETROS:
   -----------
   @_Id_Usuario_Ejecutor  : Quien realiza la operación
   @_Id_Registro_Participante : ID del registro en Capacitaciones_Participantes
   @_Motivo_Baja : Justificación de la baja (obligatorio)
   
   ====================================================================================================== */

DELIMITER $$
-- DROP PROCEDURE IF EXISTS `SP_Dar_Baja_Participante`$$
CREATE PROCEDURE `SP_Dar_Baja_Participante`(
    IN _Id_Usuario_Ejecutor INT,
    IN _Id_Registro_Participante INT,
    IN _Motivo_Baja VARCHAR(253)
)
ProcBajarPart: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════
       DECLARACIÓN DE VARIABLES
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;
    DECLARE v_Registro_Existe INT DEFAULT 0;
    DECLARE v_Estatus_Actual INT DEFAULT 0;
    DECLARE v_Tiene_Calificacion INT DEFAULT 0;
    DECLARE v_Id_Detalle INT DEFAULT 0;
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';
    DECLARE v_Nombre_Participante VARCHAR(200) DEFAULT '';
    
    -- Constantes
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;
    
    -- Handler para errores
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 
            'ERROR TÉCNICO [500]: Error interno al procesar la baja del participante.' AS Mensaje,
            'ERROR_TECNICO' AS Accion;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 0: VALIDACIÓN DE INPUTS
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio.' AS Mensaje,
            'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;
    
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El ID del Registro de Participante es obligatorio.' AS Mensaje,
            'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;
    
    IF _Motivo_Baja IS NULL OR TRIM(_Motivo_Baja) = '' THEN
        SELECT 
            'ERROR DE ENTRADA [400]: El motivo de la baja es obligatorio para fines de auditoría.' AS Mensaje,
            'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 1: VALIDACIÓN DEL EJECUTOR
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT COUNT(*) 
    INTO v_Ejecutor_Existe
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor 
    AND Activo = 1;
    
    IF v_Ejecutor_Existe = 0 THEN
        SELECT 
            'ERROR DE PERMISOS [403]: Usuario Ejecutor no válido o inactivo.' AS Mensaje,
            'ACCESO_DENEGADO' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 2: VALIDACIÓN DEL REGISTRO DE PARTICIPANTE
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT 
        COUNT(*),
        COALESCE(`CP`.`Fk_Id_CatEstPart`, 0),
        COALESCE(`CP`.`Fk_Id_DatosCap`, 0),
        CASE WHEN `CP`.`Calificacion` IS NOT NULL 
        THEN 1 ELSE 0 END
    INTO 
        v_Registro_Existe,
        v_Estatus_Actual,
        v_Id_Detalle,
        v_Tiene_Calificacion
    FROM `Capacitaciones_Participantes` `CP`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;
    
    IF v_Registro_Existe = 0 THEN
        SELECT 
            'ERROR DE EXISTENCIA [404]: El registro de participante no existe.' AS Mensaje,
            'RECURSO_NO_ENCONTRADO' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;
    
    -- Obtener contexto para mensajes
    SELECT 
        `C`.`Numero_Capacitacion`,
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`)
    INTO v_Folio_Curso, v_Nombre_Participante
    FROM `Capacitaciones_Participantes` `CP`
    JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    JOIN `Capacitaciones` `C` ON `DC`.`Fk_Id_Capacitacion` = `C`.`Id_Capacitacion`
    JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP.Id_CapPart` = _Id_Registro_Participante;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 3: VALIDACIÓN DE REGLAS DE NEGOCIO
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- 3.1 Verificar que no esté ya dado de baja
    IF v_Estatus_Actual = c_ESTATUS_BAJA THEN
        SELECT 
            CONCAT('AVISO: El participante "', v_Nombre_Participante, 
                   '" ya tiene estatus de BAJA en el curso "', v_Folio_Curso, '".') AS Mensaje,
            'SIN_CAMBIOS' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;
    
    -- 3.2 Verificar que no tenga calificación (curso no evaluado)
    IF v_Tiene_Calificacion = 1 THEN
        SELECT 
            CONCAT('ERROR DE NEGOCIO [409]: No se puede dar de baja al participante "', v_Nombre_Participante,
                   '" porque ya tiene una calificación registrada en el curso "', v_Folio_Curso, 
                   '". El curso está en proceso de evaluación o finalizado.') AS Mensaje,
            'CONFLICTO_ESTADO' AS Accion;
        LEAVE ProcBajarPart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 4: EJECUCIÓN DEL CAMBIO DE ESTATUS
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    START TRANSACTION;
    
    UPDATE `Capacitaciones_Participantes`
    SET 
		`Fk_Id_CatEstPart` = c_ESTATUS_BAJA,
    /* [CORRECCIÓN]: Guardamos la justificación y la auditoría */
        `Justificacion` = _Motivo_Baja,
        `updated_at` = NOW(),
        `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
    WHERE `Id_CapPart` = _Id_Registro_Participante;
    
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 5: RESPUESTA EXITOSA
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT 
        CONCAT(' BAJA REGISTRADA: El participante "', v_Nombre_Participante,
               '" ha sido dado de baja del curso "', v_Folio_Curso, 
               '". Motivo: ', _Motivo_Baja, '. El cupo ha sido liberado.') AS Mensaje,
        'BAJA_EXITOSA' AS Accion;

END$$

DELIMITER ;