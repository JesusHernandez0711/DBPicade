/* ====================================================================================================
   PROCEDIMIENTO: SP_ObtenerMatrizPICADE
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. CONTEXTO OPERATIVO Y PROPÓSITO (THE "WHAT" & "FOR WHOM")
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el motor de lectura masiva diseñado para alimentar el **Grid Principal (Matriz)** del Dashboard.
   Actúa como la fuente de verdad única para la visualización de cursos, independientemente de su estado.

   [EL PROBLEMA QUE RESUELVE]: 
   La necesidad de visualizar una mezcla compleja de registros históricos, activos y archivados en una
   sola vista coherente, sin sacrificar el rendimiento por cálculos de permisos en tiempo real.

   [SOLUCIÓN ARQUITECTÓNICA - "DUMB DB, SMART APP"]: 
   Este SP adopta una postura agnóstica respecto a las reglas de negocio de la interfaz (UI).
   - NO decide qué botones mostrar (Editar vs Ver).
   - NO decide colores.
   - SOLO entrega la "Verdad Cruda" (Raw Flags) y los datos físicos.
   - DELEGA la inteligencia de decisión (RBAC) a la capa de aplicación (Laravel/Backend).

   ----------------------------------------------------------------------------------------------------
   II. ESTRATEGIA DE INTEGRIDAD (DATA CONSISTENCY)
   ----------------------------------------------------------------------------------------------------
   [PATRÓN "MAX ID SNAPSHOT"]:
   - Problema: Un curso puede tener múltiples versiones en `DatosCapacitaciones` (Historial de cambios).
   - Solución: Se utiliza una subconsulta de `MAX(Id)` agrupada por `Fk_Id_Capacitacion`.
   - Resultado: Garantiza que el reporte siempre muestre la **ÚLTIMA FOTO** conocida del curso, 
     evitando duplicidad de folios en el listado.

   ----------------------------------------------------------------------------------------------------
   III. CONTRATO DE INTERFAZ (INPUT/OUTPUT)
   ----------------------------------------------------------------------------------------------------
   - INPUT: 
     * _Id_Gerencia (INT): Filtro opcional.
     * _Fecha_Min / _Fecha_Max (DATE): Ventana de tiempo obligatoria.
   
   - OUTPUT (Banderas Lógicas Clave):
     * Activo_Padre: Estado del expediente global (Año Fiscal).
     * Activo_Hijo: Estado de la versión específica (Vigencia).
   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_ObtenerMatrizPICADE`$$

CREATE PROCEDURE `SP_ObtenerMatrizPICADE`(
    IN _Id_Gerencia INT,  -- [OPCIONAL] Filtro Organizacional (0 o NULL = Ver Todo)
    IN _Fecha_Min   DATE, -- [OBLIGATORIO] Inicio del rango (Inclusive)
    IN _Fecha_Max   DATE  -- [OBLIGATORIO] Fin del rango (Inclusive)
)
THIS_PROC: BEGIN

    /* ============================================================================================
       BLOQUE 0: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Propósito: Rechazar peticiones lógicamente imposibles antes de consultar datos.
       ============================================================================================ */
    
    /* 0.1 Validación de Ventana de Tiempo */
    IF _Fecha_Min IS NULL OR _Fecha_Max IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Las fechas de inicio y fin son obligatorias.';
    END IF;

    /* 0.2 Validación de Coherencia Temporal (Anti-Paradoja) */
    IF _Fecha_Min > _Fecha_Max THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: La fecha de inicio no puede ser posterior a la fecha de fin.';
    END IF;

    /* ============================================================================================
       BLOQUE 1: PROYECCIÓN DE DATOS (SELECT LAYER)
       Propósito: Definir las columnas que viajarán al Frontend.
       ============================================================================================ */
    SELECT 
        /* --- METADATOS TEMPORALES (Para agrupación visual en el Grid) --- */
        YEAR(`VC`.`Fecha_Inicio`)          AS `Anio`,
        MONTHNAME(`VC`.`Fecha_Inicio`)     AS `Mes_Nombre`,
        
        /* --- LLAVE DE NAVEGACIÓN (CONTEXTO) --- */
        `VC`.`Id_Detalle_de_Capacitacion`  AS `Id_Para_Click`, -- Payload para el Modal de Detalle
        
        /* --- DATOS VISUALES DEL CURSO (INFORMACIÓN HUMANA) --- */
        `VC`.`Numero_Capacitacion`         AS `Folio`,
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,
        `VC`.`Nombre_Tema`                 AS `Tema`,
        `VC`.`Nombre_Instructor`           AS `Instructor`, -- Muestra al responsable de la última versión
        `VC`.`Fecha_Inicio`,
        `VC`.`Fecha_Fin`,
        `VC`.`Nombre_Sede`                 AS `Sede`,
        
        /* --- ESTADO VISUAL (TEXTOS) --- */
        `VC`.`Estatus_Curso`               AS `Estatus_Texto`, -- Ej: "FINALIZADO", "CANCELADO"
        --  `VC`.`Codigo_Estatus`              AS `Badge_Color`,   -- Ej: "FIN", "CANC" (Para clases CSS)

        /* ==============================================================================
           BANDERAS LÓGICAS (RAW DATA FLAGS)
           Estos campos son la base para la lógica de negocio en el Backend (Laravel).
           ============================================================================== */
        `Cap`.`Activo`                     AS `Estatus_Del_Registro`, -- 1=Expediente Vivo, 0=Año Cerrado/Archivado
        -- `Latest_Row`.`Activo`              AS `Estatus_Registro_Hijo`,  -- 1=Versión Vigente, 0=Versión Histórica

        /* --- KPI MÉTRICAS (ANALÍTICA) --- */
        `VC`.`Asistentes_Meta`,
        `VC`.`Asistentes_Reales`           

    /* ============================================================================================
       BLOQUE 2: ORIGEN DE DATOS Y RELACIONES (JOINS LAYER)
       Propósito: Ensamblar la vista maestra con las tablas de control.
       ============================================================================================ */
    FROM `Picade`.`Vista_Capacitaciones` `VC`
    
    /* JOIN 1: ENLACE CON ENTIDAD PADRE (CAPACITACIONES)
       Necesario para obtener el estatus global del expediente (Activo_Padre) y filtrar por Gerencia. */
    INNER JOIN `Picade`.`Capacitaciones` `Cap` 
        ON `VC`.`Id_Capacitacion` = `Cap`.`Id_Capacitacion`

    /* JOIN 2: FILTRO DE UNICIDAD Y ACTUALIDAD (MAX ID STRATEGY)
       Esta es la unión crítica. Conecta la vista con una subconsulta que garantiza 
       traer SOLO la última versión física de cada curso. */
    INNER JOIN (
        SELECT Id_DatosCap, Activo 
        FROM `Picade`.`DatosCapacitaciones`
        WHERE Id_DatosCap IN (
            SELECT MAX(Id_DatosCap) 
            FROM `Picade`.`DatosCapacitaciones` 
            GROUP BY Fk_Id_Capacitacion
        )
    ) `Latest_Row` ON `VC`.`Id_Detalle_de_Capacitacion` = `Latest_Row`.`Id_DatosCap`

    /* ============================================================================================
       BLOQUE 3: MOTOR DE FILTRADO (WHERE LAYER)
       Propósito: Aplicar los criterios de búsqueda del usuario.
       ============================================================================================ */
    WHERE 
        /* 3.1 FILTRO ORGANIZACIONAL (OPCIONAL)
           Si _Id_Gerencia es NULL o 0, el filtro se anula (Ver Todo). */
        (_Id_Gerencia IS NULL OR _Id_Gerencia <= 0 OR `Cap`.`Fk_Id_CatGeren` = _Id_Gerencia)
        
        AND 
        
        /* 3.2 FILTRO DE RANGO TEMPORAL (OBLIGATORIO) 
           Aplica sobre la Fecha de Inicio del curso. 
           Laravel ya calculó si esto es un Trimestre, Semestre o Rango Libre. */
        (`VC`.`Fecha_Inicio` BETWEEN _Fecha_Min AND _Fecha_Max)

    /* ============================================================================================
       BLOQUE 4: ORDENAMIENTO (PRESENTATION LAYER)
       Propósito: Definir la experiencia inicial del usuario.
       ============================================================================================ */
    /* Lógica: Mostrar lo más reciente arriba (DESC) para acceso inmediato a la operación actual. */
    ORDER BY `VC`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;