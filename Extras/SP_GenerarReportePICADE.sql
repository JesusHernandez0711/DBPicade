USE Picade;

/* ====================================================================================================
   PROCEDIMIENTO: SP_GenerarReportePICADE
   ====================================================================================================
   OBJETIVO: 
   Alimentar la vista "PICADE ANUAL" con capacidad de Drill-Down (Navegación profunda).
   
   FILOSOFÍA DE DATOS:
   Aquí NO IMPORTA si el curso está "Archivado" o "Activo" en la operación diaria. 
   Lo que importa es la HISTORIA. Si el curso sucedió en 2024, debe salir en el reporte 2024.
   Solo se excluyen los cursos "Cancelados" (que nunca ocurrieron).
   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_GenerarReportePICADE`$$

CREATE PROCEDURE `SP_GenerarReportePICADE`(
    IN _Anio            INT,          -- Ej: 2025 (OBLIGATORIO - Define la pestaña PICADE)
    IN _Id_Gerencia     INT,          -- Ej: 5 (Opcional: NULL para ver todas las gerencias)
    IN _Tipo_Periodo    VARCHAR(20),  -- 'ANUAL', 'SEMESTRAL', 'TRIMESTRAL', 'MENSUAL'
    IN _Numero_Periodo  INT           -- Ej: Si es MENSUAL, 1=Enero. Si es SEMESTRAL, 2=2do Semestre.
)
BEGIN
    SELECT 
        /* 1. DATOS DE CLASIFICACIÓN TEMPORAL (Para agrupar en la vista) */
        YEAR(`VC`.`Fecha_Inicio`)          AS `Anio`,
        
        CASE 
            WHEN MONTH(`VC`.`Fecha_Inicio`) BETWEEN 1 AND 6 THEN '1er Semestre'
            ELSE '2do Semestre' 
        END                                AS `Semestre`,
        
        QUARTER(`VC`.`Fecha_Inicio`)       AS `Trimestre`,
        MONTHNAME(`VC`.`Fecha_Inicio`)     AS `Mes_Nombre`,
        
        /* 2. DATOS DE CLASIFICACIÓN ORGANIZACIONAL (Para comparar Gerencias) */
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,
        
        /* 3. DATOS DEL CURSO (El detalle) */
        `VC`.`Numero_Capacitacion`         AS `Folio`,
        `VC`.`Nombre_Tema`                 AS `Tema`,
        `VC`.`Nombre_Tipo_Instruccion`     AS `Tipo_Curso`, -- Teórico/Práctico
        `VC`.`Nombre_Instructor`           AS `Instructor`,
        `VC`.`Fecha_Inicio`,
        `VC`.`Fecha_Fin`,
        `VC`.`Nombre_Sede`                 AS `Sede`,
        
        /* 4. MÉTRICAS PARA GRÁFICAS (Lo que vas a sumar/promediar en el Excel/Dashboard) */
        `VC`.`Asistentes_Programados`      AS `Meta_Asistentes`,
        `VC`.`Asistentes_Reales`           AS `Asistentes_Reales`,
        `VC`.`Duracion_Horas`              AS `Horas_Curso`,
        /* Cálculo: Horas Hombre = Duración * Asistentes */
        (`VC`.`Duracion_Horas` * `VC`.`Asistentes_Reales`) AS `Horas_Hombre_Capacitacion`,
        
        /* 5. ESTATUS FINAL (Para saber si se cumplió) */
        `VC`.`Estatus_Curso`,
        `VC`.`Codigo_Estatus`

    FROM `Picade`.`Vista_Capacitaciones` `VC`
    
    /* JOIN TÉCNICO: Para usar la fecha real del padre y asegurar consistencia */
    INNER JOIN `Picade`.`Capacitaciones` `Cap` ON `VC`.`Id_Capacitacion` = `Cap`.`Id_Capacitacion`

    WHERE 
        /* REGLA DE ORO DEL REPORTE: Usamos la versión "Oficial" (Estatus_del_Registro=1) 
           del detalle, para no contar versiones borrador. */
        `VC`.`Estatus_del_Registro` = 1
        
        /* FILTRO 1: EL AÑO (La Pestaña Principal) */
        AND YEAR(`VC`.`Fecha_Inicio`) = _Anio
        
        /* FILTRO 2: LA GERENCIA (Si el usuario eligió una específica) */
        AND (_Id_Gerencia IS NULL OR _Id_Gerencia = 0 OR `Cap`.`Fk_Id_CatGeren` = _Id_Gerencia)
        
        /* FILTRO 3: PERIODICIDAD DINÁMICA */
        AND (
            (_Tipo_Periodo = 'ANUAL') -- Trae todo el año
            OR 
            (_Tipo_Periodo = 'SEMESTRAL' AND (
                (_Numero_Periodo = 1 AND MONTH(`VC`.`Fecha_Inicio`) <= 6) OR
                (_Numero_Periodo = 2 AND MONTH(`VC`.`Fecha_Inicio`) > 6)
            ))
            OR
            (_Tipo_Periodo = 'TRIMESTRAL' AND QUARTER(`VC`.`Fecha_Inicio`) = _Numero_Periodo)
            OR
            (_Tipo_Periodo = 'MENSUAL' AND MONTH(`VC`.`Fecha_Inicio`) = _Numero_Periodo)
        )
    
    /* ORDENAMIENTO: Cronológico para que el reporte se lea como una historia */
    ORDER BY `VC`.`Fecha_Inicio` ASC, `VC`.`Clave_Gerencia_Solicitante` ASC;

END$$

DELIMITER ;