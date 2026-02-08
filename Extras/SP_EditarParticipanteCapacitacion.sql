
/* ======================================================================================================
   PROCEDIMIENTO 3: SP_EditarParticipanteCapacitacion
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Actualizar la calificación y/o porcentaje de asistencia de un participante.
   
   REGLAS DE NEGOCIO:
   ------------------
   1. El registro de participante debe existir.
   2. No se puede actualizar si el participante está de BAJA.
   3. La calificación debe estar entre 0 y 100.
   4. El porcentaje de asistencia debe estar entre 0 y 100.
   5. Al asignar calificación, el estatus cambia automáticamente (APROBADO/REPROBADO).
   
   ====================================================================================================== */

DELIMITER $$
-- DROP PROCEDURE IF EXISTS `SP_EditarParticipanteCapacitacion`$$
CREATE PROCEDURE `SP_EditarParticipanteCapacitacion`(
    IN _Id_Usuario_Ejecutor INT,
    IN _Id_Registro_Participante INT,
    IN _Calificacion DECIMAL(5,2),
    IN _Porcentaje_Asistencia DECIMAL(5,2),
    IN _Id_Estatus_Resultado INT,  -- NULL = Calcular automático basado en calificación
    IN _Observaciones VARCHAR(253) -- [NUEVO] Feedback cualitativo (Opcional)
)
ProcUpdatResulPart: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════
       DECLARACIÓN DE VARIABLES
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    /* VARIABLES */
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;
    DECLARE v_Registro_Existe INT DEFAULT 0;
    DECLARE v_Estatus_Actual INT DEFAULT 0;
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';
    DECLARE v_Nombre_Participante VARCHAR(200) DEFAULT '';
    DECLARE v_Nuevo_Estatus INT DEFAULT 0;
    
    -- Constantes de estatus
    DECLARE c_ESTATUS_ASISTIO INT DEFAULT 2;
    DECLARE c_ESTATUS_APROBADO INT DEFAULT 3;
    DECLARE c_ESTATUS_REPROBADO INT DEFAULT 4;
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;
    DECLARE c_CALIFICACION_MINIMA_APROBATORIA DECIMAL(5,2) DEFAULT 70.00;
    
    -- Handler
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 
            'ERROR TÉCNICO [500]: Error interno al actualizar resultados.' AS Mensaje,
            'ERROR_TECNICO' AS Accion;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 0: VALIDACIÓN DE INPUTS
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;
    
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Registro de Participante es obligatorio.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;
    
    -- Validar rango de calificación
    IF _Calificacion IS NOT NULL AND (_Calificacion < 0 OR _Calificacion > 100) THEN
        SELECT 'ERROR DE ENTRADA [400]: La calificación debe estar entre 0 y 100.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;
    
    -- Validar rango de asistencia
    IF _Porcentaje_Asistencia IS NOT NULL AND (_Porcentaje_Asistencia < 0 OR _Porcentaje_Asistencia > 100) THEN
        SELECT 'ERROR DE ENTRADA [400]: El porcentaje de asistencia debe estar entre 0 y 100.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 1: VALIDACIONES DE EXISTENCIA
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT COUNT(*) INTO v_Ejecutor_Existe
    FROM Usuarios WHERE Id_Usuario = _Id_Usuario_Ejecutor AND Activo = 1;
    
    IF v_Ejecutor_Existe = 0 THEN
        SELECT 'ERROR DE PERMISOS [403]: Usuario Ejecutor no válido.' AS Mensaje, 'ACCESO_DENEGADO' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;
    
    SELECT 
        COUNT(*),
        COALESCE(`CP`.`Fk_Id_CatEstPart`, 0)
    INTO v_Registro_Existe, v_Estatus_Actual
    FROM `Capacitaciones_Participantes` `CP`
    WHERE `CP.Id_CapPart` = _Id_Registro_Participante;
    
    IF v_Registro_Existe = 0 THEN
        SELECT 'ERROR DE EXISTENCIA [404]: El registro de participante no existe.' AS Mensaje, 'RECURSO_NO_ENCONTRADO' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;
    
    -- Obtener contexto
    SELECT 
        `C`.`Numero_Capacitacion`,
        CONCAT(`IP`.`Nombre`, ' ', `IP`.`Apellido_Paterno`)
    INTO v_Folio_Curso, v_Nombre_Participante
    FROM `Capacitaciones_Participantes` `CP`
    JOIN `DatosCapacitaciones` `DC` ON `CP`.`Fk_Id_DatosCap` = `DC`.`Id_DatosCap`
    JOIN `Capacitaciones` `C` ON `DC`.`Fk_Id_Capacitacion` = `C`.`Id_Capacitacion`
    JOIN `Usuarios` `U` ON `CP`.`Fk_Id_Usuario` = `U`.`Id_Usuario`
    JOIN `Info_Personal` `IP` ON `U`.`Fk_Id_InfoPer` = `IP`.`Id_InfoPer`
    WHERE `CP`.`Id_CapPart` = _Id_Registro_Participante;
    
    -- No se puede actualizar participante dado de baja
    IF v_Estatus_Actual = c_ESTATUS_BAJA THEN
        SELECT 
            CONCAT('ERROR DE NEGOCIO [409]: No se pueden actualizar resultados del participante "', 
                   v_Nombre_Participante, '" porque está dado de BAJA.') AS Mensaje,
            'CONFLICTO_ESTADO' AS Accion;
        LEAVE ProcUpdatResulPart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 2: DETERMINAR NUEVO ESTATUS
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    IF _Id_Estatus_Resultado IS NOT NULL THEN
        -- Usar estatus proporcionado explícitamente
        SET v_Nuevo_Estatus = _Id_Estatus_Resultado;
    ELSEIF _Calificacion IS NOT NULL THEN
        -- Calcular automáticamente basado en calificación
        IF _Calificacion >= c_CALIFICACION_MINIMA_APROBATORIA THEN
            SET v_Nuevo_Estatus = c_ESTATUS_APROBADO;
        ELSE
            SET v_Nuevo_Estatus = c_ESTATUS_REPROBADO;
        END IF;
    ELSEIF _Porcentaje_Asistencia IS NOT NULL THEN
        -- Solo asistencia, sin calificación
        SET v_Nuevo_Estatus = c_ESTATUS_ASISTIO;
    ELSE
        -- Mantener estatus actual
        SET v_Nuevo_Estatus = v_Estatus_Actual;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 3: EJECUCIÓN DE LA ACTUALIZACIÓN
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    START TRANSACTION;
    
    UPDATE `Capacitaciones_Participantes`
    SET 
        `Calificacion` = COALESCE(_Calificacion, `Calificacion`),
        `PorcentajeAsistencia` = COALESCE(_Porcentaje_Asistencia, `PorcentajeAsistencia`),
        `Fk_Id_CatEstPart` = v_Nuevo_Estatus,
        
        /* AQUÍ ESTÁ EL CAMBIO: */
        /* Si mandan observación, la guardamos. Si mandan NULL, respetamos lo que ya había (o lo dejamos NULL). */
        `Justificacion` = COALESCE(_Observaciones, `Justificacion`),
        
        `updated_at` = NOW(),
        `Fk_Id_Usuario_Updated_By` = _Id_Usuario_Ejecutor
    WHERE `Id_CapPart` = _Id_Registro_Participante;
    
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 4: RESPUESTA EXITOSA
       ═══════════════════════════════════════════════════════════════════════════════════ */
       
        /* RESPUESTA */
    SELECT 
        CONCAT('RESULTADO GUARDADO: "', v_Nombre_Participante, '". ',
               IF(_Calificacion IS NOT NULL, CONCAT('Nota: ', _Calificacion, '. '), ''),
               IF(_Observaciones IS NOT NULL AND _Observaciones != '', ' (Con observaciones).', '')
        ) AS Mensaje,
        'ACTUALIZADO' AS Accion;

END$$

DELIMITER ;