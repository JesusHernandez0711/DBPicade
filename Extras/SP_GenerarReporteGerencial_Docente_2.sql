/* ======================================================================================================
   PROCEDIMIENTO: SP_GenerarReporteGerencial_Docente
   ======================================================================================================
   IDENTIFICADOR:  SP_GenerarReporteGerencial_Docente
   MÓDULO:         BUSINESS INTELLIGENCE (BI) / ANALÍTICA GERENCIAL
   
   1. DESCRIPCIÓN FUNCIONAL:
   -------------------------
   Este procedimiento constituye el motor analítico para la toma de decisiones de la alta gerencia.
   Extrae indicadores clave de desempeño (KPIs) divididos en dos dimensiones:
   A. EFICIENCIA OPERATIVA: Capacidad de acreditación por cada Gerencia solicitante.
   B. CALIDAD DOCENTE: Desempeño y tasa de fricción (reprobación) por instructor.

   2. ARQUITECTURA DE INTEGRIDAD (FORENSIC LAYERS):
   -----------------------------------------------
   A. INTEGRIDAD TEMPORAL: Valida la coherencia de rangos de fecha y sanitiza entradas nulas.
   B. INTEGRIDAD POR ID (FK-STRICT): Los cálculos de éxito/fracaso se basan en IDs de catálogo (3, 4, 9),
      eliminando la ambigüedad de las comparaciones por cadenas de texto.
   C. INTEGRIDAD DE EXCLUSIÓN: Filtra automáticamente cursos cancelados o en diseño (ID 8) para 
      no contaminar la estadística con datos pre-operativos.

   3. CONTRATO DE SALIDA (DATASETS):
   ---------------------------------
   - DATASET 1 (GERENCIAS): Métricas acumuladas por centro de costos / área.
   - DATASET 2 (INSTRUCTORES): Ranking de los 10 instructores con mayor volumen de alumnos atendidos.
   ====================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_GenerarReporteGerencial_Docente`$$

CREATE PROCEDURE `SP_GenerarReporteGerencial_Docente`(
    IN _Fecha_Inicio DATE, /* Fecha de inicio del periodo a auditar */
    IN _Fecha_Fin DATE     /* Fecha de fin del periodo a auditar */
)
ProcBI: BEGIN

    /* -----------------------------------------------------------------------------------
       SECCIÓN 1: DECLARACIÓN DE CONSTANTES Y SANITIZACIÓN TEMPORAL
       Se establecen los rangos de búsqueda y se mapean los IDs críticos del sistema.
       ----------------------------------------------------------------------------------- */
    
    -- Manejo de Fechas: Si los parámetros son NULL, se establece un horizonte histórico absoluto.
    DECLARE v_Fecha_Ini DATE DEFAULT COALESCE(_Fecha_Inicio, '1990-01-01');
    DECLARE v_Fecha_Fin DATE DEFAULT COALESCE(_Fecha_Fin, '2030-12-31');

    -- [CONSTANTES DE ESTATUS - BASADO EN DICCIONARIO PICADE]
    DECLARE c_ST_PART_ACREDITADO    INT DEFAULT 3; -- @St_PartAcre
    DECLARE c_ST_PART_NO_ACREDITADO INT DEFAULT 4; -- @St_PartNoAcre
    DECLARE c_ST_CURSO_CANCELADO    INT DEFAULT 8; -- @St_Canc

    /* -----------------------------------------------------------------------------------
       SECCIÓN 2: VALIDACIÓN DE INTEGRIDAD TEMPORAL (VAL-0)
       Previene errores de lógica donde la fecha final sea menor a la inicial.
       ----------------------------------------------------------------------------------- */
    IF v_Fecha_Ini > v_Fecha_Fin THEN
        SELECT 
            'ERROR DE LÓGICA [400]: La fecha de inicio no puede ser posterior a la fecha de fin.' AS Mensaje, 
            'VALIDACION_TEMPORAL_FALLIDA' AS Accion;
        LEAVE ProcBI;
    END IF;

    /* -----------------------------------------------------------------------------------
       SECCIÓN 3: DATASET 1 - MÉTRICAS DE EFICIENCIA POR GERENCIA
       Calcula el volumen de impacto y la tasa de éxito terminal por cada unidad organizacional.
       ----------------------------------------------------------------------------------- */
    SELECT 
        'RESUMEN_GERENCIAL' AS Mensaje,
        `VGP`.`Gerencia_Solicitante` AS `Gerencia`,
        COUNT(`VGP`.`Id_Registro_Participante`) AS `Total_Inscritos`,
        
        -- Cálculo de Aprobados mediante ID 3 (Acreditado)
        SUM(CASE WHEN `CP`.`Fk_Id_CatEstPart` = c_ST_PART_ACREDITADO THEN 1 ELSE 0 END) AS `Total_Aprobados`,

        -- Cálculo de Reprobados mediante ID 4 (No Acreditado)
        SUM(CASE WHEN `CP`.`Fk_Id_CatEstPart` = c_ST_PART_NO_ACREDITADO THEN 1 ELSE 0 END) AS `Total_Reprobados`,
        
        -- KPI: Eficiencia Terminal (Porcentaje de éxito sobre el total atendido)
        ROUND(
            (SUM(CASE WHEN `CP`.`Fk_Id_CatEstPart` = c_ST_PART_ACREDITADO THEN 1 ELSE 0 END) / COUNT(*)) * 100, 
            2
        ) AS `Porcentaje_Eficiencia`
        
    FROM `Picade`.`Vista_Gestion_de_Participantes` `VGP`
    -- Unión con tabla física para validación estricta por IDs de estatus
    INNER JOIN `Picade`.`capacitaciones_participantes` `CP` ON `VGP`.`Id_Registro_Participante` = `CP`.`Id_CapPart`
    INNER JOIN `Picade`.`datoscapacitaciones` `DC` ON `VGP`.`Id_Detalle_de_Capacitacion` = `DC`.`Id_DatosCap`
    
    WHERE `VGP`.`Fecha_Inicio` BETWEEN v_Fecha_Ini AND v_Fecha_Fin
      -- Excluir cursos cancelados para no sesgar la eficiencia (Basado en ID 8)
      AND `DC`.`Fk_Id_CatEstCap` != c_ST_CURSO_CANCELADO 
    GROUP BY `VGP`.`Gerencia_Solicitante`
    ORDER BY `Porcentaje_Eficiencia` DESC;

    /* -----------------------------------------------------------------------------------
       SECCIÓN 4: DATASET 2 - CALIDAD Y DESEMPEÑO DOCENTE
       Identifica el volumen de instrucción y la tasa de fricción por instructor.
       ----------------------------------------------------------------------------------- */
    SELECT 
        'RESUMEN_DOCENTE' AS Mensaje,
        IFNULL(`VGP`.`Instructor_Asignado`, 'SIN INSTRUCTOR ASIGNADO') AS `Instructor`,
        COUNT(DISTINCT `VGP`.`Folio_Curso`) AS `Cursos_Impartidos`,
        COUNT(`VGP`.`Id_Registro_Participante`) AS `Alumnos_Atendidos`,
        
        -- Conteo de fracaso académico (ID 4)
        SUM(CASE WHEN `CP`.`Fk_Id_CatEstPart` = c_ST_PART_NO_ACREDITADO THEN 1 ELSE 0 END) AS `Alumnos_Reprobados`,
        
        -- KPI: Tasa de Reprobación (Indica posible rigor excesivo o falta de claridad pedagógica)
        ROUND(
            (SUM(CASE WHEN `CP`.`Fk_Id_CatEstPart` = c_ST_PART_NO_ACREDITADO THEN 1 ELSE 0 END) / COUNT(*)) * 100, 
            2
        ) AS `Tasa_Reprobacion`
        
    FROM `Picade`.`Vista_Gestion_de_Participantes` `VGP`
    INNER JOIN `Picade`.`capacitaciones_participantes` `CP` ON `VGP`.`Id_Registro_Participante` = `CP`.`Id_CapPart`
    INNER JOIN `Picade`.`datoscapacitaciones` `DC` ON `VGP`.`Id_Detalle_de_Capacitacion` = `DC`.`Id_DatosCap`
    
    WHERE `VGP`.`Fecha_Inicio` BETWEEN v_Fecha_Ini AND v_Fecha_Fin
      -- Filtro de integridad: Excluir cursos cancelados o eliminados
      AND `DC`.`Fk_Id_CatEstCap` != c_ST_CURSO_CANCELADO
      
    GROUP BY `VGP`.`Instructor_Asignado`
    ORDER BY `Alumnos_Atendidos` DESC -- Priorizamos mostrar a los que tienen mayor carga de trabajo
    LIMIT 10; 

END$$

DELIMITER ;

-- Ejecutar para ver todo el historial (desde el año 2000 hasta hoy)
CALL SP_GenerarReporteGerencial_Docente('2000-01-01', '2026-12-31');

-- Ejecutar para el año fiscal actual
CALL SP_GenerarReporteGerencial_Docente(NULL, NULL);

DROP PROCEDURE IF EXISTS `SP_GenerarReporteGerencial_Docente`;