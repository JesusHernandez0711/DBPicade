DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_GenerarReporteGerencial_Docente`$$

CREATE PROCEDURE `SP_GenerarReporteGerencial_Docente`(
    IN _Fecha_Inicio DATE,
    IN _Fecha_Fin DATE
)
ProcBI: BEGIN
    
    -- Rango de fechas por defecto muy amplio
    DECLARE v_Fecha_Ini DATE DEFAULT COALESCE(_Fecha_Inicio, '1990-01-01');
    DECLARE v_Fecha_Fin DATE DEFAULT COALESCE(_Fecha_Fin, '2030-12-31');

    /* ════════════════════════════════════════════════════════════════════════════
       TABLA 1: EFICIENCIA POR GERENCIA (Esta ya funcionaba bien)
       ════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        `Gerencia_Solicitante` AS `Gerencia`,
        COUNT(*) AS `Total_Inscritos`,
        
        SUM(CASE 
            WHEN UPPER(`Resultado_Final`) IN ('APROBADO', 'ACREDITADO', 'CERTIFICADO', 'COMPETENTE') THEN 1 
            ELSE 0 
        END) AS `Total_Aprobados`,

        SUM(CASE 
            WHEN UPPER(`Resultado_Final`) IN ('REPROBADO', 'NO ACREDITADO', 'NO COMPETENTE', 'NO APROBADO') THEN 1 
            ELSE 0 
        END) AS `Total_Reprobados`,
        
        ROUND(
            (SUM(CASE 
                WHEN UPPER(`Resultado_Final`) IN ('APROBADO', 'ACREDITADO', 'CERTIFICADO', 'COMPETENTE') THEN 1 
                ELSE 0 
             END) / COUNT(*)) * 100, 
            2
        ) AS `Porcentaje_Eficiencia`
        
    FROM `Picade`.`Vista_Gestion_de_Participantes`
    WHERE `Fecha_Inicio` BETWEEN v_Fecha_Ini AND v_Fecha_Fin
      AND UPPER(`Estatus_Global_Curso`) NOT IN ('CANCELADO', 'EN DISEÑO') 
    GROUP BY `Gerencia_Solicitante`
    ORDER BY `Porcentaje_Eficiencia` DESC;

    /* ════════════════════════════════════════════════════════════════════════════
       TABLA 2: CALIDAD DOCENTE (CORREGIDA PARA MOSTRAR TODO)
       ════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        -- Usamos IFNULL por si el instructor se borró o no se asignó
        IFNULL(`Instructor_Asignado`, 'SIN INSTRUCTOR') AS `Instructor`,
        COUNT(DISTINCT `Folio_Curso`) AS `Cursos_Impartidos`,
        COUNT(*) AS `Total_Alumnos_Atendidos`,
        
        SUM(CASE 
            WHEN UPPER(`Resultado_Final`) IN ('REPROBADO', 'NO ACREDITADO', 'NO COMPETENTE', 'NO APROBADO') THEN 1 
            ELSE 0 
        END) AS `Total_Reprobados`,
        
        /* TASA DE REPROBACIÓN */
        ROUND(
            (SUM(CASE 
                WHEN UPPER(`Resultado_Final`) IN ('REPROBADO', 'NO ACREDITADO', 'NO COMPETENTE', 'NO APROBADO') THEN 1 
                ELSE 0 
             END) / COUNT(*)) * 100, 
            2
        ) AS `Tasa_Reprobacion`
        
    FROM `Picade`.`Vista_Gestion_de_Participantes`
    WHERE `Fecha_Inicio` BETWEEN v_Fecha_Ini AND v_Fecha_Fin
      -- [CAMBIO CRÍTICO]: 
      -- Antes buscábamos solo 'FINALIZADO'. 
      -- Ahora aceptamos TODO lo que NO sea Cancelado para que aparezcan tus datos de prueba.
      AND UPPER(`Estatus_Global_Curso`) NOT IN ('CANCELADO', 'ELIMINADO', 'EN DISEÑO')
      
    GROUP BY `Instructor_Asignado`
    ORDER BY `Total_Reprobados` DESC -- Ordenamos por quién reprueba más gente
    LIMIT 10; 

END$$

DELIMITER ;


-- Ejecutar para ver todo el historial (desde el año 2000 hasta hoy)
CALL SP_GenerarReporteGerencial_Docente('2000-01-01', '2026-12-31');

-- Ejecutar para el año fiscal actual
CALL SP_GenerarReporteGerencial_Docente(NULL, NULL);

DROP PROCEDURE IF EXISTS `SP_GenerarReporteGerencial_Docente`;