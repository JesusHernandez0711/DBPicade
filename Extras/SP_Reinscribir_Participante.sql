
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
DROP PROCEDURE IF EXISTS `SP_Reinscribir_Participante`$$
CREATE PROCEDURE `SP_Reinscribir_Participante`(
    IN _Id_Usuario_Ejecutor INT,
    IN _Id_Registro_Participante INT,
    IN _Motivo_Reinscripcion VARCHAR(500)
)
ProcReinsPart: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════
       DECLARACIÓN DE VARIABLES
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;
    DECLARE v_Registro_Existe INT DEFAULT 0;
    DECLARE v_Estatus_Actual INT DEFAULT 0;
    DECLARE v_Id_Detalle INT DEFAULT 0;
    DECLARE v_Id_Capacitacion_Padre INT DEFAULT 0;
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';
    DECLARE v_Nombre_Participante VARCHAR(200) DEFAULT '';
    DECLARE v_Cupo_Maximo INT DEFAULT 0;
    DECLARE v_Asientos_Ocupados INT DEFAULT 0;
    DECLARE v_Estatus_Curso INT DEFAULT 0;
    DECLARE v_Es_Estatus_Final INT DEFAULT 0;
    
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
        LEAVE ProcReinsPart; -- ← Usar la etiqueta
    END IF;
    
    IF _Id_Registro_Participante IS NULL OR _Id_Registro_Participante <= 0 THEN
        SELECT 'ERROR [400]: El ID del Registro de Participante es obligatorio.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcReinsPart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 1: VALIDACIONES DE EXISTENCIA
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT COUNT(*) INTO v_Ejecutor_Existe
    FROM Usuarios WHERE Id_Usuario = _Id_Usuario_Ejecutor AND Activo = 1;
    
    IF v_Ejecutor_Existe = 0 THEN
        SELECT 'ERROR [403]: Usuario Ejecutor no válido.' AS Mensaje, 'ACCESO_DENEGADO' AS Accion;
        LEAVE ProcReinsPart; -- ← Usar la etiqueta
    END IF;
    
    SELECT 
        COUNT(*),
        COALESCE(CP.Fk_Id_CatEstPart, 0),
        COALESCE(CP.Fk_Id_DatosCap, 0)
    INTO v_Registro_Existe, v_Estatus_Actual, v_Id_Detalle
    FROM Capacitaciones_Participantes CP
    WHERE CP.Id_CapPart = _Id_Registro_Participante;
    
    IF v_Registro_Existe = 0 THEN
        SELECT 'ERROR [404]: El registro de participante no existe.' AS Mensaje, 'RECURSO_NO_ENCONTRADO' AS Accion;
        LEAVE ProcReinsPart; -- ← Usar la etiqueta
    END IF;
    
    -- Obtener contexto
    SELECT 
        C.Numero_Capacitacion,
        C.Id_Capacitacion,
        C.Asistentes_Programados,
        CONCAT(IP.Nombre, ' ', IP.Apellido_Paterno),
        DC.Fk_Id_CatEstCap
    INTO v_Folio_Curso, v_Id_Capacitacion_Padre, v_Cupo_Maximo, v_Nombre_Participante, v_Estatus_Curso
    FROM Capacitaciones_Participantes CP
    JOIN DatosCapacitaciones DC ON CP.Fk_Id_DatosCap = DC.Id_DatosCap
    JOIN Capacitaciones C ON DC.Fk_Id_Capacitacion = C.Id_Capacitacion
    JOIN Usuarios U ON CP.Fk_Id_Usuario = U.Id_Usuario
    JOIN Info_Personal IP ON U.Fk_Id_InfoPer = IP.Id_InfoPer
    WHERE CP.Id_CapPart = _Id_Registro_Participante;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 2: VALIDACIÓN DE REGLAS DE NEGOCIO
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- 2.1 Verificar que esté dado de baja
    IF v_Estatus_Actual != c_ESTATUS_BAJA THEN
        SELECT 
            CONCAT('AVISO: El participante "', v_Nombre_Participante, 
                   '" NO está dado de baja. Su estatus actual no requiere reinscripción.') AS Mensaje,
            'SIN_CAMBIOS' AS Accion;
        LEAVE ProcReinsPart; -- ← Usar la etiqueta
    END IF;
    
    -- 2.2 Verificar que el curso no esté en estatus final
    SELECT Es_Final INTO v_Es_Estatus_Final
    FROM Cat_Estatus_Capacitacion WHERE Id_CatEstCap = v_Estatus_Curso;
    
    IF v_Es_Estatus_Final = 1 THEN
        SELECT 
            CONCAT('ERROR [409]: No se puede reinscribir en el curso "', v_Folio_Curso, 
                   '" porque ya está FINALIZADO, CANCELADO o ARCHIVADO.') AS Mensaje,
            'CONFLICTO_ESTADO' AS Accion;
        LEAVE ProcReinsPart; -- ← Usar la etiqueta
    END IF;
    
    -- 2.3 Verificar cupo disponible
    SELECT COUNT(*) INTO v_Asientos_Ocupados
    FROM Capacitaciones_Participantes
    WHERE Fk_Id_DatosCap = v_Id_Detalle
      AND Fk_Id_CatEstPart NOT IN (c_ESTATUS_BAJA);
    
    IF v_Asientos_Ocupados >= v_Cupo_Maximo THEN
        SELECT 
            CONCAT('ERROR [409]: CUPO LLENO. No hay espacio disponible para reinscribir al participante en "', 
                   v_Folio_Curso, '".') AS Mensaje,
            'CUPO_LLENO' AS Accion;
        LEAVE ProcReinsPart; -- ← Usar la etiqueta
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 3: EJECUCIÓN DE LA REINSCRIPCIÓN
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    START TRANSACTION;
    
    UPDATE Capacitaciones_Participantes
    SET Fk_Id_CatEstPart = c_ESTATUS_INSCRITO
    WHERE Id_CapPart = _Id_Registro_Participante;
    
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 4: RESPUESTA EXITOSA
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    SELECT 
        CONCAT('REINSCRIPCIÓN EXITOSA: El participante "', v_Nombre_Participante,
               '" ha sido reactivado en el curso "', v_Folio_Curso, '". ',
               COALESCE(CONCAT('Motivo: ', _Motivo_Reinscripcion), '')) AS Mensaje,
        'REINSCRITO' AS Accion;

END$$
DELIMITER ;