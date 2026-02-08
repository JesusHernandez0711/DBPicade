/* ====================================================================================================
   PROCEDIMEINTO: SP_Dashboard_ResumenGerencial_
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. CONTEXTO OPERATIVO Y PROPÓSITO
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Motor de analítica segmentada por Unidades de Negocio (Gerencias).
   Genera las "Micro-Tarjetas" que aparecen sobre el Grid Principal cuando se selecciona un año.

   [OBJETIVO DE NEGOCIO]: 
   Responder instantáneamente: "¿Quién está capacitándose más este año?" y "¿Quién tiene más cancelaciones?".
   
   [INTERACCIÓN UI]:
   Cada tarjeta devuelta contiene el `Id_Gerencia`. Al dar clic en una tarjeta, el Frontend debe:
   1. Tomar ese ID.
   2. Recargar `SP_ObtenerMatrizPICADE` pasando ese ID como filtro.

   ----------------------------------------------------------------------------------------------------
   II. ESTRATEGIA TÉCNICA
   ----------------------------------------------------------------------------------------------------
   - "Time-Boxed Analytics": A diferencia del resumen anual, este reporte es sensible al contexto temporal.
     Solo calcula métricas dentro de la ventana de tiempo solicitada (ej: Año Fiscal Actual).
   - "Hardcoded ID Optimization": Uso de IDs fijos (4=Fin, 8=Canc) para velocidad extrema.
   - "Latest Snapshot": Filtra duplicados históricos para no inflar los números de las gerencias.

   ----------------------------------------------------------------------------------------------------
   III. CONTRATO DE INTERFAZ
   ----------------------------------------------------------------------------------------------------
   - INPUT: _Fecha_Min, _Fecha_Max (Define el "Tablero" actual).
   - OUTPUT: Lista de Gerencias con sus KPIs, ordenada por volumen de operación (Mayor a menor).
   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Dashboard_ResumenGerencial`$$

CREATE PROCEDURE `SP_Dashboard_ResumenGerencial`(
    IN _Fecha_Min DATE, -- Inicio del Periodo (ej: '2026-01-01')
    IN _Fecha_Max DATE  -- Fin del Periodo    (ej: '2026-12-31')
)
THIS_PROC: BEGIN

    /* ============================================================================================
       FASE 0: PROGRAMACIÓN DEFENSIVA
       ============================================================================================ */
    IF _Fecha_Min IS NULL OR _Fecha_Max IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR [400]: Se requiere un rango de fechas para calcular el resumen gerencial.';
    END IF;

    /* ============================================================================================
       FASE 1: CÁLCULO DE KPIs POR GERENCIA
       ============================================================================================ */
    SELECT 
        /* --- IDENTIDAD DE LA TARJETA (Para el Click en UI) --- */
        `Ger`.`Id_CatGeren`                AS `Id_Filtro`,   -- El ID que se enviará a la Matriz
        `Ger`.`Clave`                      AS `Clave_Gerencia`,
        `Ger`.`Nombre`                     AS `Nombre_Gerencia`, -- (Opcional, si es muy largo usar Clave)

        /* --- KPI: VOLUMEN OPERATIVO --- */
        COUNT(DISTINCT `Cap`.`Numero_Capacitacion`) AS `Total_Cursos`,

        /* --- KPI: DESGLOSE DE SALUD (SEMAFORIZACIÓN) --- */
        /* Verdes: Finalizados (ID 4)  
           Suma Finalizados (4) Y Archivados (10).
           Lógica: Si está archivado, es porque se finalizó correctamente. */
        SUM(CASE 
            WHEN `DC`.`Fk_Id_CatEstCap` IN (4, 10) THEN 1 
            ELSE 0 
        END) AS `Finalizados`,
        
        /* Rojos: Cancelados (ID 8) */
        SUM(CASE WHEN `DC`.`Fk_Id_CatEstCap` = 8 THEN 1 ELSE 0 END) AS `Cancelados`,
        
        /* Azules/Amarillos: En Proceso (Ni Fin, Ni Canc, Ni Arch) */
        SUM(CASE WHEN `DC`.`Fk_Id_CatEstCap` NOT IN (4, 8, 10) THEN 1 ELSE 0 END) AS `En_Proceso`,

        /* --- KPI: IMPACTO HUMANO --- */
        SUM(`DC`.`AsistentesReales`)       AS `Personas_Impactadas`

    /* ============================================================================================
       FASE 2: ORIGEN DE DATOS (JOINS & SNAPSHOT)
       ============================================================================================ */
    FROM `Picade`.`DatosCapacitaciones` `DC`

    /* Join con Padre para obtener la Gerencia */
    INNER JOIN `Picade`.`Capacitaciones` `Cap` 
        ON `DC`.`Fk_Id_Capacitacion` = `Cap`.`Id_Capacitacion`

    /* Join con Catálogo de Gerencias (Para obtener Clave y Nombre) */
    INNER JOIN `Picade`.`Cat_Gerencias_Activos` `Ger` 
        ON `Cap`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`

    /* Join de Unicidad (Latest Snapshot) */
    INNER JOIN (
        SELECT MAX(`Id_DatosCap`) as `MaxId` 
        FROM `Picade`.`DatosCapacitaciones` 
        GROUP BY `Fk_Id_Capacitacion`
    ) `Latest` ON `DC`.`Id_DatosCap` = `Latest`.`MaxId`

    /* ============================================================================================
       FASE 3: FILTRADO Y AGRUPACIÓN
       ============================================================================================ */
    WHERE 
        /* Solo mostramos gerencias que tuvieron actividad en ESTE periodo */
        (`DC`.`Fecha_Inicio` BETWEEN _Fecha_Min AND _Fecha_Max)
        
        /* Opcional: Si quieres excluir expedientes archivados globalmente, descomenta esto: */
        -- AND `Cap`.`Activo` = 1 

    GROUP BY 
        `Ger`.`Id_CatGeren`, 
        `Ger`.`Clave`, 
        `Ger`.`Nombre`

    /* ============================================================================================
       FASE 4: ORDENAMIENTO (UX)
       ============================================================================================ */
    /* Las gerencias con más carga de trabajo aparecen primero (Izquierda a Derecha en UI) */
    ORDER BY `Total_Cursos` DESC;

END$$

DELIMITER ;