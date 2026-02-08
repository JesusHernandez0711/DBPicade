/* ======================================================================================================
   PROCEDIMIENTO 7: SP_Reinscribir_Participante
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Reactivar un participante que estaba dado de BAJA, cambiando su estatus a INSCRITO.
   
   REGLAS DE NEGOCIO:
   ------------------
   1. El participante debe existir y estar en estatus BAJA.
   2. Debe haber cupo disponible para reactivarlo.
   3. El curso debe estar en estatus operativo (no FINALIZADO/CANCELADO/ARCHIVADO).
   
   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_Reinscribir_Participante`$$

CREATE PROCEDURE `SP_Reinscribir_Participante`(
    IN _Id_Usuario_Ejecutor INT,
    IN _Id_Registro_Participante INT,
    IN _Motivo_Reinscripcion VARCHAR(253)
)
ProcReinsPart: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════
       DECLARACIÓN DE VARIABLES
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;
    DECLARE v_Registro_Existe INT DEFAULT 0;
    DECLARE v_Estatus_Actual INT DEFAULT 0;
    DECLARE v_Id_Detalle INT DEFAULT 0;
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';
    DECLARE v_Nombre_Participante VARCHAR(200) DEFAULT '';
    DECLARE v_Cupo_Maximo INT DEFAULT 0;
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;
    DECLARE v_Curso_Activo INT DEFAULT 0; -- Para verificar si el curso sigue vivo
    
    -- Constantes
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1;
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;
    
    -- Handler
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'ERROR TÉCNICO [500]: Error interno al procesar la reinscripción.' AS Mensaje, 'ERROR_TECNICO' AS Accion;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 0: VALIDACIÓN DE INPUTS
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SELECT 'ERROR [400]: El ID del Usuario Ejecutor es obligatorio.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcReinsPart;
    END IF;
    
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 THEN
        SELECT 'ERROR [400]: El ID del Registro de Participante es obligatorio.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcReinsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 1: VALIDACIONES DE EXISTENCIA
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    /* 1.1 Ejecutor */
    SELECT COUNT(*) INTO v_Ejecutor_Existe
    FROM Usuarios WHERE Id_Usuario = _Id_Usuario_Ejecutor AND Activo = 1;
    
    IF v_Ejecutor_Existe = 0 THEN
        SELECT 'ERROR [403]: Usuario Ejecutor no válido.' AS Mensaje, 'ACCESO_DENEGADO' AS Accion;
        LEAVE ProcReinsPart;
    END IF;
    
    /* 1.2 Registro del Participante y Contexto */
    SELECT 
        COUNT(*),
        COALESCE(CP.Fk_Id_CatEstPart, 0),
        COALESCE(CP.Fk_Id_DatosCap, 0),
        
        -- Contexto para Mensajes
        C.Numero_Capacitacion,
        C.Asistentes_Programados,
        CONCAT(IP.Nombre, ' ', IP.Apellido_Paterno),
        DC.Activo -- Verificamos si la versión del curso está Activa (1) o Archivada (0)
        
    INTO v_Registro_Existe, v_Estatus_Actual, v_Id_Detalle, 
         v_Folio_Curso, v_Cupo_Maximo, v_Nombre_Participante, v_Curso_Activo
         
    FROM Capacitaciones_Participantes CP
    JOIN DatosCapacitaciones DC ON CP.Fk_Id_DatosCap = DC.Id_DatosCap
    JOIN Capacitaciones C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
    JOIN Usuarios U ON CP.Fk_Id_Usuario = U.Id_Usuario
    JOIN Info_Personal IP ON U.Fk_Id_InfoPer = IP.Id_InfoPer
    WHERE CP.Id_CapPart = _Id_Registro_Participante;
    
    IF v_Registro_Existe = 0 THEN
        SELECT 'ERROR [404]: El registro de participante no existe.' AS Mensaje, 'RECURSO_NO_ENCONTRADO' AS Accion;
        LEAVE ProcReinsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 2: VALIDACIÓN DE REGLAS DE NEGOCIO
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- 2.1 Verificar que esté dado de BAJA (Solo se puede reinscribir a alguien dado de baja)
    IF v_Estatus_Actual != c_ESTATUS_BAJA THEN
        SELECT 
            CONCAT('AVISO: El participante "', v_Nombre_Participante, 
                   '" NO está dado de baja (Estatus actual: ', v_Estatus_Actual, '). No requiere reinscripción.') AS Mensaje,
            'SIN_CAMBIOS' AS Accion;
        LEAVE ProcReinsPart;
    END IF;
    
    -- 2.2 Verificar que el curso siga VIGENTE (Activo = 1)
    IF v_Curso_Activo = 0 THEN
        SELECT 
            CONCAT('ERROR [409]: No se puede reinscribir en el curso "', v_Folio_Curso, 
                   '" porque esta versión ya fue FINALIZADA o ARCHIVADA.') AS Mensaje,
            'CONFLICTO_ESTADO' AS Accion;
        LEAVE ProcReinsPart;
    END IF;
    
    -- 2.3 Verificar cupo disponible (Contando a todos MENOS los de baja)
    SELECT COUNT(*) INTO v_Asientos_Ocupados
    FROM Capacitaciones_Participantes
    WHERE Fk_Id_DatosCap = v_Id_Detalle
      AND Fk_Id_CatEstPart != c_ESTATUS_BAJA; -- Misma lógica que en la Vista
    
    IF v_Asientos_Ocupados >= v_Cupo_Maximo THEN
        SELECT 
            CONCAT('ERROR [409]: CUPO LLENO (', v_Asientos_Ocupados, '/', v_Cupo_Maximo, '). No hay espacio para reinscribir a "', 
                   v_Nombre_Participante, '".') AS Mensaje,
            'CUPO_LLENO' AS Accion;
        LEAVE ProcReinsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 3: EJECUCIÓN (CON AUDITORÍA)
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    START TRANSACTION;
    
    UPDATE Capacitaciones_Participantes
    SET 
        Fk_Id_CatEstPart = c_ESTATUS_INSCRITO, -- Vuelve a estar Activo (ID 1)
        
        /* [IMPORTANTE] Guardamos el motivo en la columna Justificación */
        Justificacion = CONCAT('REINSCRIPCIÓN: ', COALESCE(_Motivo_Reinscripcion, 'Sin motivo')),
        
        /* [IMPORTANTE] Auditoría de Modificación */
        updated_at = NOW(),
        Fk_Id_Usuario_Updated_By = _Id_Usuario_Ejecutor
        
    WHERE Id_CapPart = _Id_Registro_Participante;
    
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 4: RESPUESTA EXITOSA
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT 
        CONCAT('REINSCRIPCIÓN EXITOSA: "', v_Nombre_Participante,
               '" reactivado en "', v_Folio_Curso, '".') AS Mensaje,
        'REINSCRITO' AS Accion;

END$$
DELIMITER ;