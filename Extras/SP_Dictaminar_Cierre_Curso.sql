USE Picade;

/* ======================================================================================================
   PROCEDIMIENTO: SP_Dictaminar_Cierre_Curso
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Realizar el CIERRE ADMINISTRATIVO Y ESTADÍSTICO de un curso.
   Calcula automáticamente si el curso fue "Exitoso" (Acreditado) basándose en el
   rendimiento del grupo.
   
   REGLA DE NEGOCIO (KPI DE CALIDAD):
   - Si el % de alumnos aprobados es >= 70%: El curso se marca como ACREDITADO (ID 6).
   - Si el % de alumnos aprobados es < 70%: El curso se marca como NO ACREDITADO (ID 7).
   
   NOTAS TÉCNICAS:
   - Ignora a los alumnos con estatus BAJA (ID 5) para el cálculo.
   - Actualiza el estatus del curso y agrega una nota de auditoría en Observaciones.
   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_Dictaminar_Cierre_Curso`$$

CREATE PROCEDURE `SP_Dictaminar_Cierre_Curso`(
    IN _Id_Detalle_Capacitacion INT,
    IN _Id_Usuario_Auditor      INT
)
THIS_PROC: BEGIN

    /* -------------------------------------------------------------------
       DECLARACIÓN DE VARIABLES
       ------------------------------------------------------------------- */
    DECLARE v_Total_Participantes INT DEFAULT 0;
    DECLARE v_Total_Aprobados     INT DEFAULT 0;
    DECLARE v_Porcentaje_Exito    DECIMAL(5,2) DEFAULT 0.00;
    DECLARE v_Nuevo_Estatus_Curso INT;
    
    /* IDs FIJOS DEL CATÁLOGO DE CURSOS (Tus IDs confirmados) */
    DECLARE c_CURSO_ACREDITADO    INT DEFAULT 6; 
    DECLARE c_CURSO_NO_ACREDITADO INT DEFAULT 7; 
    
    /* IDs FIJOS DEL CATÁLOGO DE PARTICIPANTES */
    DECLARE c_ALUMNO_APROBADO     INT DEFAULT 3; -- El alumno pasó
    DECLARE c_ALUMNO_BAJA         INT DEFAULT 5; -- El alumno canceló (no cuenta)

    /* KPI DE CALIDAD */
    DECLARE c_KPI_MINIMO_APROBACION DECIMAL(5,2) DEFAULT 70.00;

    /* HANDLER DE SEGURIDAD */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; 
    END;

    /* -------------------------------------------------------------------
       FASE 1: VALIDACIONES PREVIAS
       ------------------------------------------------------------------- */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [400]: ID de capacitación inválido.';
    END IF;

    IF _Id_Usuario_Auditor IS NULL OR _Id_Usuario_Auditor <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [400]: ID de auditor obligatorio para trazabilidad.';
    END IF;

    /* -------------------------------------------------------------------
       FASE 2: CÁLCULO ESTADÍSTICO (MATH ENGINE)
       ------------------------------------------------------------------- */
    
    -- 2.1 UNIVERSO: Contar Total de Participantes EVALUABLES (Todos menos las BAJAS)
    SELECT COUNT(*) INTO v_Total_Participantes
    FROM Capacitaciones_Participantes
    WHERE Fk_Id_DatosCap = _Id_Detalle_Capacitacion
    AND Fk_Id_CatEstPart != c_ALUMNO_BAJA;

    -- Validación: No se puede cerrar un curso vacío o donde todos se dieron de baja.
    IF v_Total_Participantes = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [409]: No se puede dictaminar el curso. No hay participantes activos (evaluables) registrados.';
    END IF;

    -- 2.2 ÉXITOS: Contar cuántos APROBARON individualmente (Estatus 3)
    SELECT COUNT(*) INTO v_Total_Aprobados
    FROM Capacitaciones_Participantes
    WHERE Fk_Id_DatosCap = _Id_Detalle_Capacitacion
    AND Fk_Id_CatEstPart = c_ALUMNO_APROBADO;

    -- 2.3 KPI: Calcular el Porcentaje de Éxito del Grupo
    SET v_Porcentaje_Exito = (v_Total_Aprobados / v_Total_Participantes) * 100;

    /* -------------------------------------------------------------------
       FASE 3: EL VEREDICTO (DICTAMINACIÓN)
       ------------------------------------------------------------------- */
    
    IF v_Porcentaje_Exito >= c_KPI_MINIMO_APROBACION THEN
        -- CASO ÉXITO: El grupo pasó la prueba de calidad (>70%)
        SET v_Nuevo_Estatus_Curso = c_CURSO_ACREDITADO; -- ID 6
    ELSE
        -- CASO ALERTA: Demasiados reprobados (<70%). El curso NO se acredita.
        SET v_Nuevo_Estatus_Curso = c_CURSO_NO_ACREDITADO; -- ID 7
    END IF;

    /* -------------------------------------------------------------------
       FASE 4: APLICACIÓN DEL CAMBIO Y CIERRE (COMMIT)
       ------------------------------------------------------------------- */
    START TRANSACTION;

    -- Actualizamos el estatus del curso basándonos en la estadística
    UPDATE DatosCapacitaciones
    SET 
        Fk_Id_CatEstCap = v_Nuevo_Estatus_Curso,
        
        /* INYECCIÓN DE EVIDENCIA EN BITÁCORA */
        Observaciones = CONCAT_WS('\n\n', Observaciones, 
            CONCAT('[SISTEMA - DICTAMEN AUTOMÁTICO] ', DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i'), 
                   '\n- Total Evaluados: ', v_Total_Participantes,
                   '\n- Total Aprobados: ', v_Total_Aprobados,
                   '\n- Índice de Calidad: ', v_Porcentaje_Exito, '%',
                   '\n- Veredicto: ', IF(v_Nuevo_Estatus_Curso = c_CURSO_ACREDITADO, 'ACREDITADO (Cumple meta)', 'NO ACREDITADO (Falla meta)')
            )
        ),
        
        /* AUDITORÍA */
        updated_at = NOW(),
        Fk_Id_Usuario_DatosCap_Updated_by = _Id_Usuario_Auditor
        
    WHERE Id_DatosCap = _Id_Detalle_Capacitacion;

    COMMIT;

    /* -------------------------------------------------------------------
       FASE 5: FEEDBACK AL USUARIO
       ------------------------------------------------------------------- */
    SELECT 
        'DICTAMINADO' AS Accion,
        v_Nuevo_Estatus_Curso AS Nuevo_Id_Estatus,
        v_Porcentaje_Exito AS Indice_Calidad,
        CONCAT(
            'El curso ha sido cerrado. ',
            'Aprobación del grupo: ', v_Porcentaje_Exito, '%. ',
            'Estatus asignado: ', IF(v_Nuevo_Estatus_Curso = 6, 'ACREDITADO', 'NO ACREDITADO')
        ) AS Mensaje;

END$$

DELIMITER ;

