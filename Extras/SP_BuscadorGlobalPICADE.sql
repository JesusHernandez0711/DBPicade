/* ====================================================================================================
   PROCEDIMEINTO: SP_BuscadorGlobalPICADE
   ====================================================================================================
   
   1. FICHA TÉCNICA
   ----------------
   - Nombre: SP_BuscadorGlobalPICADE
   - Objetivo: Motor de Búsqueda Global (GPS) compatible con el Grid de la Matriz.
   
   2. ESTRATEGIA DE "ESPEJO" (MIRROR OUTPUT)
   -----------------------------------------
   Este SP ha sido refactorizado para devolver EXACTAMENTE las mismas columnas y nombres 
   que el `SP_ObtenerMatrizPICADE`.
   
   Esto permite que el Frontend reutilice el mismo componente visual (Tabla/Card) para 
   mostrar los resultados de la búsqueda, sin necesidad de mapeos adicionales.

   3. DATO EXTRA (GPS)
   -------------------
   Solo se añade la columna `Anio_Ubicacion` para permitir la lógica de redirección entre 
   pestañas anuales en el Frontend.
   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_BuscadorGlobalPICADE`$$

CREATE PROCEDURE `SP_BuscadorGlobalPICADE`(
    IN _TerminoBusqueda VARCHAR(50) -- Lo que escribe el usuario
)
BEGIN
    /* Validación de seguridad para evitar table scans masivos */
    IF LENGTH(_TerminoBusqueda) < 2 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BÚSQUEDA: Ingrese al menos 2 caracteres.';
    END IF;

    SELECT 
        /* ==============================================================================
           1. DATO GPS (Exclusivo del Buscador)
           Laravel usa esto para saber si redirige al usuario a otro año.
           ============================================================================== */
        YEAR(`VC`.`Fecha_Inicio`)          AS `Anio_Ubicacion`,

        /* ==============================================================================
           2. ESTRUCTURA ESPEJO DE LA MATRIZ (Idéntica a SP_ObtenerMatrizPICADE)
           ============================================================================== */
        
        /* --- METADATOS TEMPORALES --- */
        YEAR(`VC`.`Fecha_Inicio`)          AS `Anio`,
        MONTHNAME(`VC`.`Fecha_Inicio`)     AS `Mes_Nombre`,
        
        /* --- LLAVE DE NAVEGACIÓN (CONTEXTO) --- */
        `VC`.`Id_Capacitacion`,            -- ID Padre
        `VC`.`Id_Detalle_de_Capacitacion`, -- ID Hijo (Payload del botón)
        
        /* --- DATOS VISUALES DEL CURSO --- */
        `VC`.`Numero_Capacitacion`         AS `Folio`,
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,
        `VC`.`Nombre_Tema`                 AS `Tema`,
        `VC`.`Nombre_Instructor`           AS `Instructor`,
        `VC`.`Fecha_Inicio`,
        `VC`.`Fecha_Fin`,
        `VC`.`Nombre_Sede`                 AS `Sede`,
        
        /* --- ESTADO VISUAL (TEXTOS) --- */
        `VC`.`Estatus_Curso`               AS `Estatus_Texto`,

        /* --- BANDERAS LÓGICAS (RAW DATA) --- */
        `Cap`.`Activo`                     AS `Estatus_Del_Registro`, -- 1=Vivo, 0=Archivado

        /* --- KPI MÉTRICAS --- */
        `VC`.`Asistentes_Meta`,
        `VC`.`Asistentes_Reales`

    /* ============================================================================================
       ORIGEN DE DATOS (JOINS)
       ============================================================================================ */
    FROM `Picade`.`Vista_Capacitaciones` `VC`
    
    /* JOIN CON PADRE (Para Estado Global y Busqueda por Gerencia) */
    INNER JOIN `Picade`.`Capacitaciones` `Cap` 
        ON `VC`.`Id_Capacitacion` = `Cap`.`Id_Capacitacion`

    /* JOIN PARA INTEGRIDAD (Snapshot) Y BÚSQUEDA (Tema) */
    INNER JOIN `Picade`.`DatosCapacitaciones` `Latest_Row` 
        ON `VC`.`Id_Detalle_de_Capacitacion` = `Latest_Row`.`Id_DatosCap`
    
    /* JOINS DE CATÁLOGOS (Para poder buscar por texto dentro de ellos) */
    INNER JOIN `Picade`.`Cat_Temas` `Tem` 
        ON `Latest_Row`.`Fk_Id_Tema` = `Tem`.`Id_Tema`
        
    INNER JOIN `Picade`.`Cat_Gerencias_Activos` `Ger` 
        ON `Cap`.`Fk_Id_CatGeren` = `Ger`.`Id_CatGeren`

    /* ============================================================================================
       MOTOR DE BÚSQUEDA (WHERE)
       Aquí aplicamos la lógica "Cross-Year" (Sin filtro de fechas)
       ============================================================================================ */
    WHERE 
        /* Estrategia MAX ID: Asegura que buscamos sobre la versión actual del curso */
        `Latest_Row`.`Id_DatosCap` IN (
            SELECT MAX(Id_DatosCap) FROM `Picade`.`DatosCapacitaciones` GROUP BY Fk_Id_Capacitacion
        )
        
        AND (
            /* Búsqueda por los 3 vectores solicitados */
            `VC`.`Numero_Capacitacion` LIKE CONCAT('%', _TerminoBusqueda, '%')   -- A) Folio
            OR
            `Ger`.`Clave` LIKE CONCAT('%', _TerminoBusqueda, '%')                -- B) Clave Gerencia
            OR
            `Tem`.`Codigo` LIKE CONCAT('%', _TerminoBusqueda, '%')               -- C) Código Tema
        )

    /* ============================================================================================
       ORDENAMIENTO
       ============================================================================================ */
    /* Priorizamos lo más reciente para que el usuario encuentre rápido lo actual */
    ORDER BY `VC`.`Fecha_Inicio` DESC
    
    LIMIT 50; -- Tope de seguridad para no saturar la red si la búsqueda es muy genérica (ej: "A")

END$$

DELIMITER ;