USE Picade;

/* ====================================================================================================
   PROCEDIMIENTO: SP_EjecutarCierreDeCurso (El Juez Automático)
   ====================================================================================================
   OBJETIVO: 
   Evaluar masivamente a los participantes de un curso y asignar su estatus final 
   basado en las reglas de negocio estrictas.

   REGLAS DE NEGOCIO (LOGIC GATE):
   1. SI Curso = CANCELADO -> Todos pasan a "CURSO CANCELADO".
   2. SI Curso = FINALIZADO/ARCHIVADO -> Se evalúa desempeño:
      A) Sin Asistencia/Calificación -> "BAJA POR INASISTENCIA".
      B) Con Asistencia pero Calif < Mínima -> "NO APROBADO".
      C) Con Asistencia y Calif >= Mínima -> "APROBADO".
   ==================================================================================================== */

DELIMITER $$

CREATE PROCEDURE `SP_EjecutarCierreDeCurso`(
    IN _Id_DatosCap INT,  -- El ID del Curso específico
    IN _Id_Usuario_Ejecutor INT -- Quién ordenó el cierre
)
BEGIN
    /* Variables para leer la configuración del curso */
    DECLARE v_Estatus_Curso_EsFinal TINYINT;
    DECLARE v_Codigo_Estatus_Curso VARCHAR(50);
    
    /* IDs de los Estatus de Participante (Deben coincidir con tu Catálogo) */
    /* NOTA: En producción, estos IDs se buscarían dinámicamente por Código */
    DECLARE C_ID_APROBADO INT DEFAULT 3;
    DECLARE C_ID_REPROBADO INT DEFAULT 4;
    DECLARE C_ID_BAJA_INASISTENCIA INT DEFAULT 5;
    DECLARE C_ID_CURSO_CANCELADO INT DEFAULT 6;
    
    /* Umbrales de Aprobación (Configurables) */
    DECLARE C_MIN_ASISTENCIA DECIMAL(5,2) DEFAULT 80.00;
    DECLARE C_MIN_CALIFICACION DECIMAL(5,2) DEFAULT 80.00;

    START TRANSACTION;

    /* 1. Obtener información del Curso */
    SELECT EC.Es_Final, EC.Codigo
    INTO v_Estatus_Curso_EsFinal, v_Codigo_Estatus_Curso
    FROM DatosCapacitaciones DC
    INNER JOIN Cat_Estatus_Capacitacion EC ON DC.Fk_Id_CatEstCap = EC.Id_CatEstCap
    WHERE DC.Id_DatosCap = _Id_DatosCap;

    /* ----------------------------------------------------------------------
       CASO 1: EL CURSO FUE CANCELADO
       Lógica: Arrasar con todos. No importa si tenían 100 de calificación.
       ---------------------------------------------------------------------- */
    IF v_Codigo_Estatus_Curso = 'CANCELADO' THEN
        
        UPDATE Capacitaciones_Participantes
        SET Fk_Id_CatEstPart = C_ID_CURSO_CANCELADO,
            updated_at = NOW()
        WHERE Fk_Id_DatosCap = _Id_DatosCap;
        
        SELECT 'CIERRE POR CANCELACIÓN: Todos los participantes han sido marcados como CANCELADOS.' AS Mensaje;
    
    /* ----------------------------------------------------------------------
       CASO 2: EL CURSO FUE FINALIZADO / ARCHIVADO (EVALUACIÓN)
       Lógica: El Juez revisa uno por uno (Set-based update).
       ---------------------------------------------------------------------- */
    ELSEIF v_Estatus_Curso_EsFinal = 1 THEN
        
        /* A) Detectar y castigar INASISTENCIAS (Fantasmas) */
        /* Condición: Asistencia nula o 0 */
        UPDATE Capacitaciones_Participantes
        SET Fk_Id_CatEstPart = C_ID_BAJA_INASISTENCIA,
            updated_at = NOW()
        WHERE Fk_Id_DatosCap = _Id_DatosCap
          AND (PorcentajeAsistencia IS NULL OR PorcentajeAsistencia = 0);

        /* B) Detectar REPROBADOS (Asistieron pero no saben) */
        /* Condición: Asistencia >= Mínima PERO Calificación < Mínima */
        UPDATE Capacitaciones_Participantes
        SET Fk_Id_CatEstPart = C_ID_REPROBADO,
            updated_at = NOW()
        WHERE Fk_Id_DatosCap = _Id_DatosCap
          AND PorcentajeAsistencia >= C_MIN_ASISTENCIA
          AND (Calificacion < C_MIN_CALIFICACION OR Calificacion IS NULL);

        /* C) Detectar APROBADOS (Cumplieron todo) */
        /* Condición: Asistencia >= Mínima Y Calificación >= Mínima */
        UPDATE Capacitaciones_Participantes
        SET Fk_Id_CatEstPart = C_ID_APROBADO,
            updated_at = NOW()
        WHERE Fk_Id_DatosCap = _Id_DatosCap
          AND PorcentajeAsistencia >= C_MIN_ASISTENCIA
          AND Calificacion >= C_MIN_CALIFICACION;
          
        SELECT 'CIERRE DE EVALUACIÓN: Se han calculado los estatus finales (Aprobado/Reprobado/Baja) masivamente.' AS Mensaje;

    ELSE
        /* Si el curso sigue vivo (Programado/En Curso), no hacemos nada */
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR: No se puede ejecutar el cierre. El curso aún se encuentra en estatus OPERATIVO.';
    END IF;

    COMMIT;
END$$

DELIMITER ;