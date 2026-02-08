USE Picade;

/* ====================================================================================================
   ARTEFACTO DE BASE DE DATOS: SP_ListarCapacitaciones_MainGrid
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre: SP_ListarCapacitaciones_MainGrid
   - Tipo: Consulta de Proyección Filtrada (Filtered Projection Query)
   - Nivel de Aislamiento: Read Committed
   - Estrategia de Filtrado: "Double Lock Integrity" (Integridad de Doble Candado)
   - Dependencias: 
       * `Vista_Capacitaciones` (Fuente de datos ricos/formateados)
       * `Capacitaciones` (Fuente de verdad para el estado del Padre)
   - Autor: Arquitectura de Datos PICADE
   - Versión: 2.0 (Double Lock Security)
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento alimenta la **Tabla Principal (Dashboard)** del sistema.
   Su responsabilidad crítica es actuar como un "Filtro de Verdad", asegurando que el Coordinador
   vea EXCLUSIVAMENTE los cursos que son operativa y administrativamente válidos.
   
   Evita la contaminación visual con:
     - Registros históricos (Versiones anteriores de un curso).
     - Registros eliminados (Cursos cancelados a nivel global).
     - Registros corruptos (Detalles activos huérfanos de padres inactivos).

   3. LÓGICA DE "DOBLE CANDADO" (DOUBLE LOCK LOGIC)
   ------------------------------------------------
   Para que un registro aparezca en este listado, debe superar dos pruebas de vida simultáneas:
   
     [CANDADO 1: VIGENCIA DEL DETALLE] (Estatus_del_Registro = 1)
     Verifica que esta fila específica sea la versión más reciente y autorizada del plan de estudios.
     Esto filtra las versiones antiguas (historial).
     
     [CANDADO 2: VITALIDAD DEL PADRE] (Cap.Activo = 1)
     Verifica que el "Expediente General" (Cabecera) no haya sido dado de baja administrativa 
     (Soft Delete Global).
     Esto filtra los cursos que fueron eliminados totalmente, aunque su último detalle siguiera marcado como activo.

   4. JUSTIFICACIÓN DE ARQUITECTURA (HYBRID JOIN)
   ----------------------------------------------
   Aunque la `Vista_Capacitaciones` contiene la gran mayoría de los datos, realizamos un 
   INNER JOIN explícito con la tabla física `Capacitaciones` (`Cap`).
   
   ¿Por qué?
   Para aplicar el [CANDADO 2] sin necesidad de alterar la definición de la Vista (lo cual podría
   impactar otros reportes de auditoría que sí necesitan ver cursos eliminados).
   Esta estrategia mantiene la Vista "agnóstica" y el SP "opinado/seguro".

   ==================================================================================================== */

DELIMITER $$

-- Eliminamos la versión anterior para aplicar la nueva lógica de seguridad.
DROP PROCEDURE IF EXISTS `SP_ListarCapacitaciones_MainGrid`$$

CREATE PROCEDURE `SP_ListarCapacitaciones_MainGrid`()
BEGIN
    /* ============================================================================================
       BLOQUE PRINCIPAL DE CONSULTA
       Recuperación de datos optimizada para el renderizado de Grids (Tablas HTML/JS).
       ============================================================================================ */
    SELECT 
        /* ----------------------------------------------------------------------------------------
           GRUPO A: IDENTIFICADORES DE ACCIÓN
           Estos IDs son invisibles al usuario pero vitales para los botones de acción del Grid:
           - Botón [Ver Detalle] -> Usa `Id_Version_Actual`
           - Botón [Eliminar Curso] -> Usa `Id_Padre`
           ---------------------------------------------------------------------------------------- */
        `VC`.`Id_Capacitacion`             AS `Id_Padre`,          -- ID de la Cabecera (Para borrado global)
        `VC`.`Id_Detalle_de_Capacitacion`  AS `Id_Version_Actual`, -- ID del Detalle (Para consulta específica)
        
        /* ----------------------------------------------------------------------------------------
           GRUPO B: COLUMNAS VISIBLES (IDENTIDAD)
           Datos que permiten al usuario identificar rápidamente el curso.
           ---------------------------------------------------------------------------------------- */
        `VC`.`Numero_Capacitacion`         AS `Folio`,    -- Ej: CAP-2026-001
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`, -- Ej: RH-CAP
        `VC`.`Nombre_Tema`                 AS `Tema`,     -- Ej: SEGURIDAD INDUSTRIAL
        
        /* ----------------------------------------------------------------------------------------
           GRUPO C: COLUMNAS VISIBLES (LOGÍSTICA EN TIEMPO REAL)
           Muestra la configuración vigente (la última versión aprobada).
           ---------------------------------------------------------------------------------------- */
        `VC`.`Nombre_Instructor`           AS `Instructor`, -- Solo el nombre, sin apellidos (o como venga en la vista)
        `VC`.`Fecha_Inicio`,
        `VC`.`Fecha_Fin`,
        `VC`.`Nombre_Sede`                 AS `Sede`,
        
        /* ----------------------------------------------------------------------------------------
           GRUPO D: SEMÁFOROS Y ESTADO
           Datos visuales para badges de colores y toma de decisiones rápidas.
           ---------------------------------------------------------------------------------------- */
        `VC`.`Estatus_Curso`               AS `Estatus`,        -- Texto Humano (ej: PROGRAMADO)
        `VC`.`Codigo_Estatus`,                                  -- Código Técnico (ej: PROG -> Badge Azul)
        
        /* ----------------------------------------------------------------------------------------
           GRUPO E: MÉTRICAS RÁPIDAS (DASHBOARDING)
           Contadores para que el coordinador vea la salud del curso sin entrar al detalle.
           ---------------------------------------------------------------------------------------- */
        `VC`.`Asistentes_Reales`           AS `Inscritos`,      -- Cuántos hay
        `VC`.`Asistentes_Meta`             AS `Cupo_Total`      -- Cuántos caben

    FROM `Picade`.`Vista_Capacitaciones` `VC`
    
    /* --------------------------------------------------------------------------------------------
       ESTRATEGIA DE DOBLE CANDADO (DOUBLE LOCK JOIN)
       Aquí ocurre la magia de seguridad. Unimos la Vista con la Tabla Física del Padre.
       -------------------------------------------------------------------------------------------- */
    INNER JOIN `Picade`.`Capacitaciones` `Cap_Fisica`
        ON `VC`.`Id_Capacitacion` = `Cap_Fisica`.`Id_Capacitacion`
    
    /* --------------------------------------------------------------------------------------------
       FILTROS DE INTEGRIDAD (WHERE CLAUSE)
       Solo pasan los registros que cumplen ambas condiciones de vida.
       -------------------------------------------------------------------------------------------- */
    WHERE 
        /* [CANDADO 1]: El Detalle debe ser la versión vigente (Historial oculto) */
        `VC`.`Estatus_del_Registro` = 1
        
        AND
        
        /* [CANDADO 2]: La Cabecera debe estar activa (Eliminados ocultos) */
        `Cap_Fisica`.`Activo` = 1
    
    /* --------------------------------------------------------------------------------------------
       ORDENAMIENTO PREFERENTE
       Los cursos más próximos a iniciar o recién creados aparecen primero.
       -------------------------------------------------------------------------------------------- */
    ORDER BY `VC`.`Fecha_Inicio` DESC, `VC`.`Id_Detalle_de_Capacitacion` DESC;

END$$

DELIMITER ;