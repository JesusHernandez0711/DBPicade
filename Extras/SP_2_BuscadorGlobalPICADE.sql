/* ====================================================================================================
   PROCEDIMIENTO: SP_BuscadorGlobalPICADE_
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. CONTEXTO OPERATIVO Y PROPÓSITO (THE "WHAT" & "FOR WHOM")
   ----------------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Es el "Sabueso" del sistema. Un motor de búsqueda global diseñado para localizar expedientes
   perdidos en el tiempo, ignorando los filtros de Año Fiscal o Gerencia que limitan al dashboard.

   [EL PROBLEMA QUE RESUELVE]: 
   El "Punto Ciego Histórico". Cuando un usuario busca un folio (ej: "CAP-2022") estando en la vista
   del 2026, el grid normal no lo encuentra. Este SP escanea TODA la base de datos para hallarlo.

   [SOLUCIÓN ARQUITECTÓNICA - "MIRROR OUTPUT STRATEGY"]: 
   Este SP devuelve EXACTAMENTE la misma estructura de columnas (nombres y tipos) que el procedimiento
   maestro `SP_ObtenerMatrizPICADE`.
   - Beneficio: El Frontend (Vue/Laravel) puede reutilizar el mismo componente visual (Tabla/Card)
     para mostrar los resultados, sin necesitar adaptadores o mapeos adicionales.

   ----------------------------------------------------------------------------------------------------
   II. ESTRATEGIA DE INTEGRIDAD (DATA CONSISTENCY)
   ----------------------------------------------------------------------------------------------------
   [PATRÓN "MAX ID SNAPSHOT"]:
   Igual que la Matriz, utiliza una subconsulta de `MAX(Id)` para ignorar el historial de ediciones
   y devolver únicamente la versión vigente del curso encontrado.

   ----------------------------------------------------------------------------------------------------
   III. CONTRATO DE INTERFAZ (INPUT/OUTPUT)
   ----------------------------------------------------------------------------------------------------
   - INPUT: 
     * _TerminoBusqueda (VARCHAR): Fragmento de texto (min 2 chars).
   
   - OUTPUT (Clave para Laravel):
     * Anio: Dato crítico (GPS) para que el Frontend decida si muestra el registro o 
       sugiere una redirección (ej: "Ir al Dashboard 2022").
   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_BuscadorGlobalPICADE`$$

CREATE PROCEDURE `SP_BuscadorGlobalPICADE`(
    IN _TerminoBusqueda VARCHAR(50) -- Input del usuario (Folio, Gerencia o Tema)
)
THIS_PROC: BEGIN

    /* ============================================================================================
       FASE 0: PROGRAMACIÓN DEFENSIVA (DEFENSIVE CODING BLOCK)
       Propósito: Proteger al servidor de consultas costosas o vacías.
       ============================================================================================ */
    IF LENGTH(_TerminoBusqueda) < 2 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ADVERTENCIA DE SEGURIDAD [400]: El término de búsqueda debe tener al menos 2 caracteres.';
    END IF;

    /* ============================================================================================
       FASE 1: PROYECCIÓN DE DATOS (DATA PROJECTION LAYER)
       Objetivo: Seleccionar y etiquetar las columnas que consumirá el API de Laravel.
       ============================================================================================ */
    SELECT 
       
        /* ------------------------------------------------------------------
           GRUPO A: LLAVES DE NAVEGACIÓN (CONTEXTO TÉCNICO)
           Estos datos NO se muestran al usuario, pero son las "balas" que disparan los botones.
           ------------------------------------------------------------------ */
        `VC`.`Id_Capacitacion`,            -- ID Padre (Expediente). Útil para trazabilidad.
        `VC`.`Id_Detalle_de_Capacitacion`, -- ID Hijo (Versión). CRÍTICO: Es el payload del botón "Editar".
        
        /* ------------------------------------------------------------------
           GRUPO B: DATOS VISUALES (CAPA DE PRESENTACIÓN)
           Información humana que llena las celdas de la tabla.
           ------------------------------------------------------------------ */
        `VC`.`Numero_Capacitacion`         AS `Folio`,      -- Identificador único visual (ej: CAP-2026-001)
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,   -- Cliente interno (ej: GSPSST)
        `VC`.`Nombre_Tema`                 AS `Tema`,       -- Título del curso
        `VC`.`Duracion_Horas`			   AS `Duracion`,
        `VC`.`Nombre_Instructor`           AS `Instructor`, -- Responsable de la ejecución
        `VC`.`Nombre_Sede`                 AS `Sede`,       -- Lugar de ejecución
		`VC`.`Nombre_Modalidad`            AS `Modalidad`,
        
		/* ------------------------------------------------------------------
		   GRUPO C: METADATOS TEMPORALES
           Usados por el Frontend para agrupar visualmente (ej: Encabezados de Mes).
		------------------------------------------------------------------ */
        
		`VC`.`Fecha_Inicio`,                                -- Día 1 del curso
		`VC`.`Fecha_Fin`,                                   -- Día N del curso

         YEAR(`VC`.`Fecha_Inicio`)          AS `Anio`,       -- Año Fiscal
		MONTHNAME(`VC`.`Fecha_Inicio`)     AS `Mes`, -- Etiqueta legible (Enero, Febrero...)
        
        /* ------------------------------------------------------------------
           GRUPO D: ANALÍTICA (KPIs)
           Métricas rápidas para visualización en el grid.
           ------------------------------------------------------------------ */
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,   -- KPI Financiero (Integer)
        `VC`.`Asistentes_Reales`,

        /* ------------------------------------------------------------------
           GRUPO E: ESTADO VISUAL
           Textos pre-calculados en la Vista para mostrar al usuario.
           ------------------------------------------------------------------ */
        `VC`.`Estatus_Curso`               AS `Estatus_Texto`, -- (ej: "FINALIZADO", "CANCELADO")

        `VC`.`Observaciones`               AS `Bitacora_Notas`,           -- Justificación de esta versión

        /* ------------------------------------------------------------------
           GRUPO F: BANDERAS LÓGICAS (LOGIC FLAGS - CRITICAL)
           Aquí reside la inteligencia arquitectónica. Entregamos el estado físico puro.
           Laravel usará esto para: if (Estatus_Del_Registro == 1 && User->isAdmin()) { ... }
           ------------------------------------------------------------------ */
        `Cap`.`Activo`                     AS `Estatus_Del_Registro` -- 1 = Expediente Vivo / 0 = Archivado (Soft Delete)

    /* ============================================================================================
       FASE 2: ORIGEN DE DATOS Y RELACIONES (RELATIONAL ASSEMBLY)
       Propósito: Ensamblar la vista maestra asegurando integridad histórica.
       ============================================================================================ */
    FROM `Picade`.`Vista_Capacitaciones` `VC`
    
    /* [JOIN 1]: ENLACE CON PADRE (Para leer Estatus Global `Cap.Activo`) */
    INNER JOIN `Picade`.`Capacitaciones` `Cap` 
        ON `VC`.`Id_Capacitacion` = `Cap`.`Id_Capacitacion`

    /* [JOIN 2]: FILTRO DE ACTUALIDAD (MAX ID SNAPSHOT)
       Evita traer versiones obsoletas del mismo folio. Solo la última foto es válida. */
    INNER JOIN (
        SELECT MAX(Id_DatosCap) as MaxId 
        FROM `Picade`.`DatosCapacitaciones` 
        GROUP BY Fk_Id_Capacitacion
    ) `Latest_Row` ON `VC`.`Id_Detalle_de_Capacitacion` = `Latest_Row`.MaxId

    /* ============================================================================================
       FASE 3: MOTOR DE BÚSQUEDA GLOBAL (SEARCH ENGINE)
       Propósito: Escanear múltiples vectores sin restricción de fechas.
       ============================================================================================ */
    WHERE 
        (
            /* Vector 1: Identidad del Curso */
            `VC`.`Numero_Capacitacion` LIKE CONCAT('%', _TerminoBusqueda, '%')
            OR
            /* Vector 2: Cliente Interno */
            `VC`.`Clave_Gerencia_Solicitante` LIKE CONCAT('%', _TerminoBusqueda, '%')
            OR
            /* Vector 3: Contenido Académico */
            `VC`.`Codigo_Tema` LIKE CONCAT('%', _TerminoBusqueda, '%')
        )

    /* ============================================================================================
       FASE 4: ORDENAMIENTO (UX SORTING)
       Propósito: Priorizar lo más reciente para aumentar la relevancia del hallazgo.
       ============================================================================================ */
    ORDER BY `VC`.`Fecha_Inicio` DESC;
    /* NOTA: Se eliminó el LIMIT para permitir auditorías exhaustivas si es necesario. */

END$$

DELIMITER ;