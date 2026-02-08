/* ====================================================================================================
   PROCEDIMIENTO: SP_ObtenerMatrizPICADE
   ====================================================================================================
   
   1. FICHA TÉCNICA
   ----------------
   - Nombre: SP_ObtenerMatrizPICADE
   - Tipo: Motor de Búsqueda Multidimensional (Multidimensional Search Engine)
   
   2. VISIÓN DE NEGOCIO (ESCENARIOS CUBIERTOS)
   -------------------------------------------
   Este SP es el cerebro detrás del Grid Principal. Resuelve dinámicamente:
   
   [ESCENARIO 1: DEFAULT]: Solo llega el Año (Clic en Dashboard).
      -> Muestra TODO de ese año.
   
   [ESCENARIO 2: FILTRO GERENCIA]: Año + Id_Gerencia.
      -> Muestra todo el año, pero solo de esa Gerencia (ej: GSPSSTPARS).
      
   [ESCENARIO 3: FILTRO PERIODO]: Año + Trimestre/Mes.
      -> Muestra todas las gerencias, pero acotadas a Ene-Mar (por ejemplo).
      
   [ESCENARIO 4: FILTRO CRUZADO]: Año + Gerencia + Periodo.
      -> La búsqueda más específica: "Q1 de la Gerencia de Seguridad".

   [ESCENARIO 5: RANGO LIBRE]: Fechas personalizadas (Input Date).
      -> Ignora el año fiscal y busca entre fecha A y B.

   3. INTEGRIDAD DE DATOS
   ----------------------
   - Aplica la estrategia "MAX(ID)" para mostrar solo la última versión de cada curso.
   - Incluye registros Archivados/Cancelados para integridad histórica.
   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_ObtenerMatrizPICADE`$$

CREATE PROCEDURE `SP_ObtenerMatrizPICADE`(
    /* --- CONTEXTO PRINCIPAL (Viene de la Tarjeta) --- */
    IN _Anio            INT,          
    
    /* --- FILTROS DE NAVEGACIÓN (Opcionales: 0 o NULL si no se usan) --- */
    IN _Id_Gerencia     INT,          -- Filtro Organizacional
    IN _Tipo_Periodo    VARCHAR(20),  -- 'ANUAL', 'SEMESTRAL', 'TRIMESTRAL', 'MENSUAL', 'RANGO'
    IN _Numero_Periodo  INT,          -- 1, 2, 3... (Coordenada del periodo)
    
    /* --- RANGO PERSONALIZADO (Solo si Tipo = 'RANGO') --- */
    IN _Fecha_Inicio_Rango DATE,      
    IN _Fecha_Fin_Rango    DATE       
)
BEGIN
    SELECT 
        /* --- DATOS TEMPORALES (Para Agrupación Visual) --- */
        YEAR(`VC`.`Fecha_Inicio`)          AS `Anio`,
        MONTHNAME(`VC`.`Fecha_Inicio`)     AS `Mes_Nombre`,
        QUARTER(`VC`.`Fecha_Inicio`)       AS `Trimestre`,
        
        /* --- LLAVE DE NAVEGACIÓN --- */
        `VC`.`Id_Detalle_de_Capacitacion`  AS `Id_Para_Click`, -- Este ID abre el Modal de Detalle
        
        /* --- DATOS VISUALES DEL CURSO --- */
        `VC`.`Numero_Capacitacion`         AS `Folio`,
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,
        `VC`.`Nombre_Tema`                 AS `Tema`,
        `VC`.`Nombre_Instructor`           AS `Instructor`, -- Muestra al último instructor asignado
        `VC`.`Fecha_Inicio`,
        `VC`.`Fecha_Fin`,
        `VC`.`Nombre_Sede`                 AS `Sede`,
        
        /* --- ESTADO Y SEMÁFOROS --- */
        `VC`.`Estatus_Curso`               AS `Estatus_Texto`,
        `VC`.`Codigo_Estatus`              AS `Badge_Color`, -- Para pintar etiquetas (ej: CANC=Rojo)

        /* SEMÁFORO DE CICLO DE VIDA (¿Está gris/archivado?) */
        CASE 
            WHEN `Cap`.`Activo` = 0 THEN 'ARCHIVADO' 
            ELSE 'OPERATIVO' 
        END                                AS `Estado_Sistema`,

        /* CEREBRO DE INTERACCIÓN (¿Qué botón muestro?) 
           Regla: Solo EDITAR si el Padre vive (1) Y la Versión es actual (1). */
        CASE 
            WHEN `Cap`.`Activo` = 1 AND `Latest_Row`.`Activo` = 1 THEN 'EDITAR' 
            ELSE 'VER_DETALLE' 
        END                                AS `Accion_Permitida`,

        /* --- KPI MÉTRICAS --- */
        `VC`.`Asistentes_Meta`             AS `Meta`,
        `VC`.`Asistentes_Reales`           AS `Real`

    FROM `Picade`.`Vista_Capacitaciones` `VC`
    
    /* JOIN CON PADRE (Para filtros de Gerencia y estado Activo global) */
    INNER JOIN `Picade`.`Capacitaciones` `Cap` ON `VC`.`Id_Capacitacion` = `Cap`.`Id_Capacitacion`

    /* ----------------------------------------------------------------------------------------
       FILTRO DE UNICIDAD (MAX ID STRATEGY)
       Garantiza 1 Renglón por Folio (La última versión conocida).
       ---------------------------------------------------------------------------------------- */
    INNER JOIN (
        SELECT Id_DatosCap, Activo 
        FROM `Picade`.`DatosCapacitaciones`
        WHERE Id_DatosCap IN (
            SELECT MAX(Id_DatosCap) FROM `Picade`.`DatosCapacitaciones` GROUP BY Fk_Id_Capacitacion
        )
    ) `Latest_Row` ON `VC`.`Id_Detalle_de_Capacitacion` = `Latest_Row`.`Id_DatosCap`

    WHERE 
        /* ====================================================================================
           BLOQUE A: FILTRO DE GERENCIA (Aplica siempre si viene lleno)
           Este cubre tu caso: "Filtrar a la Gerencia GSPSSTPARS"
           ==================================================================================== */
        (_Id_Gerencia IS NULL OR _Id_Gerencia <= 0 OR `Cap`.`Fk_Id_CatGeren` = _Id_Gerencia)
        
        AND (
            /* ================================================================================
               BLOQUE B: LOGICA DE PERIODOS PREDEFINIDOS
               Cubre tus escenarios 1 (Anual), 2, 3 y 4.
               ================================================================================ */
            (
                _Tipo_Periodo <> 'RANGO' 
                AND YEAR(`VC`.`Fecha_Inicio`) = _Anio -- Candado del Año Fiscal
                AND (
                    (_Tipo_Periodo = 'ANUAL') OR -- Escenario 1: Trae todo el año
                    (_Tipo_Periodo = 'SEMESTRAL' AND ((_Numero_Periodo = 1 AND MONTH(`VC`.`Fecha_Inicio`) <= 6) OR (_Numero_Periodo = 2 AND MONTH(`VC`.`Fecha_Inicio`) > 6))) OR
                    (_Tipo_Periodo = 'TRIMESTRAL' AND QUARTER(`VC`.`Fecha_Inicio`) = _Numero_Periodo) OR -- Escenario 3 y 4
                    (_Tipo_Periodo = 'MENSUAL' AND MONTH(`VC`.`Fecha_Inicio`) = _Numero_Periodo)
                )
            )
            OR
            /* ================================================================================
               BLOQUE C: LOGICA DE RANGO LIBRE (INPUTS DATE)
               Cubre la necesidad de flexibilidad total.
               ================================================================================ */
            (
                _Tipo_Periodo = 'RANGO' AND 
                `VC`.`Fecha_Inicio` BETWEEN _Fecha_Inicio_Rango AND _Fecha_Fin_Rango
            )
        )

    /* ORDENAMIENTO CRONOLÓGICO INVERSO (Lo más nuevo arriba) */
    ORDER BY `VC`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;