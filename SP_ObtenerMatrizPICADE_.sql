
/* ====================================================================================================
   PROCEDIMIENTO: SP_ObtenerMatrizPICADE_
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre Oficial:      SP_ObtenerMatrizPICADE
   - Tipo:                Procedimiento de Lectura Masiva (Bulk Read)
   - Nivel de Aislamiento: READ COMMITTED (Lectura Confirmada)
   - Complejidad:         O(N) sobre índices agrupados (Alta Eficiencia)
   - Dependencias:        Vista_Capacitaciones, Capacitaciones, DatosCapacitaciones
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento es el **Corazón del Dashboard Operativo**. Su misión es proyectar la "Verdad Única"
   sobre el estado de la capacitación en la empresa.
   
   Resuelve el problema de la "Ambigüedad Histórica": En un sistema donde los cursos cambian de fecha,
   instructor o estatus múltiples veces, este SP garantiza que el Coordinador vea SIEMPRE Y SOLO
   la versión final vigente, ignorando los borradores o versiones previas.

   3. ARQUITECTURA DE SOLUCIÓN: "RAW DATA DELIVERY"
   ------------------------------------------------
   A diferencia de sistemas legados que incrustan HTML o lógica de colores en SQL, este SP es agnóstico.
   - NO devuelve: "Botón Rojo" o "Clase CSS".
   - SÍ devuelve: "Activo = 0" (El dato crudo).
   
   Esto permite que Laravel (Backend) y Vue (Frontend) decidan cómo pintar la interfaz sin tener que
   modificar la Base de Datos ante cambios cosméticos.

   4. MAPA DE SALIDA (OUTPUT CONTRACT)
   -----------------------------------
   - Datos de Navegación: IDs ocultos para que el Frontend sepa qué editar.
   - Datos Humanos:       Textos legibles (Folio, Tema, Instructor).
   - Banderas Lógicas:    Flags binarios (1/0) para el motor de decisiones de Laravel.
   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_ObtenerMatrizPICADE`$$

CREATE PROCEDURE `SP_ObtenerMatrizPICADE`(
    /* ------------------------------------------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       ------------------------------------------------------------------------------------------------
       Se reciben tipos estrictos para evitar inyección SQL y garantizar integridad de filtros.
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Gerencia INT,  -- [OPCIONAL] Filtro Organizacional. Si es NULL/0, se asume "Vista Global".
    IN _Fecha_Min   DATE, -- [OBLIGATORIO] Límite inferior del rango temporal (Inclusive).
    IN _Fecha_Max   DATE  -- [OBLIGATORIO] Límite superior del rango temporal (Inclusive).
)
THIS_PROC: BEGIN

    /* ============================================================================================
       FASE 0: PROGRAMACIÓN DEFENSIVA (DEFENSIVE CODING BLOCK)
       Objetivo: Validar la coherencia de la petición antes de consumir recursos del servidor.
       ============================================================================================ */
    
    /* 0.1 Integridad de Parametrización */
    /* Regla: El motor de reportes no puede adivinar fechas. Deben ser explícitas. */
    IF _Fecha_Min IS NULL OR _Fecha_Max IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: Las fechas de inicio y fin son obligatorias para delimitar el reporte.';
    END IF;

    /* 0.2 Coherencia Temporal (Anti-Paradoja) */
    /* Regla: El tiempo es lineal. El inicio no puede ocurrir después del fin. */
    IF _Fecha_Min > _Fecha_Max THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE LÓGICA [400]: Rango de fechas inválido. La fecha de inicio es posterior a la fecha de fin.';
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
        
		`VC`.`Id_Subdireccion`,
		`VC`.`Clave_Subdireccion`,
		`VC`.`Nombre_Subdireccion`,
        
		`VC`.`Id_Gerencia`,
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,   -- Cliente interno (ej: GSPSST)
        `VC`.`Nombre_Gerencia`,
        
		`VC`.`Id_Tema`,
        `VC`.`Codigo_Tema`,
        `VC`.`Nombre_Tema`                 AS `Tema`,       -- Título del curso
        `VC`.`Descripcion_Tema`,
        
        `VC`.`Tipo_Instruccion`,
        `VC`.`Duracion_Horas`			   AS `Duracion`,
        
        `VC`.`Ficha_Instructor`,
        /*`VC`.`Nombre_Instructor`           AS `Instructor`, -- Responsable de la ejecución
        `Us`.`Ficha_Usuario`                AS `Ficha_Instructor`,
        `Us`.`Apellido_Paterno_Instructor`             AS `Apellido_Paterno_Instructor`,
        `Us`.`Apellido_Materno_Instructor`             AS `Apellido_Materno_Instructor`,
        `Us`.`Nombre_Instructor`                       AS `Nombre_Instructor`,*/
        /*CONCAT(
			`VC`.`Apellido_Paterno_Instructor`, ' ',
            `VC`.`Apellido_Materno_Instructor`, ' ', 
            `VC`.`Nombre_Instructor`
		) AS `Instructor`,*/
        
         CONCAT(
			 IFNULL(`VC`.`Nombre_Instructor`,''), ' ',
			 IFNULL(`VC`.`Apellido_Materno_Instructor`,''), ' ',
			 IFNULL(`VC`.`Apellido_Paterno_Instructor`,'')
         ) AS `Instructor`,
		
		`VC`.`Id_Sedes`,
        `VC`.`Codigo_Sede`,                  --  ¡AÑADE ESTA LÍNEA PARA QUE LARAVEL LO VEA! 
		`VC`.`Nombre_Sede`                 AS `Sede`,       -- Lugar de ejecución
        
		`VC`.`Id_Modalidad`,
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
           ------------------------------------------------------------------*/
        /* -----------------------------------------------------------------------------------------
           [KPIs DE PLANEACIÓN - PLANIFICADO]
           Datos estáticos definidos al crear el curso. Representan la "Meta".
           ----------------------------------------------------------------------------------------- */

        -- Capacidad máxima teórica del aula o sala virtual.
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        
        -- Cantidad de asientos reservados manualmente por el coordinador (Override).
        -- Este valor tiene precedencia sobre el conteo automático en caso de ser mayor.
        -- Esta variable representa el total de personas que llevaron físicamente el curso pero que actualmente no tienen un registro en el sistema.
         `VC`.`Asistentes_Manuales`		  AS `No_Inscritos_en_Sistema`, 
        
		/* -----------------------------------------------------------------------------------------
           [KPIs DE OPERACIÓN - REALIDAD FÍSICA]
           Datos dinámicos calculados en tiempo real basados en la tabla de hechos.
           ----------------------------------------------------------------------------------------- */
        
        /* [CONTEO DE SISTEMA]: 
           Número exacto de filas en la tabla `Capacitaciones_Participantes` con estatus activo.
           Es la "verdad informática" de cuántos registros existen. */
        `VC`.`Participantes_Activos`       AS `Inscritos_en_Sistema`,   

        /* [IMPACTO REAL - REGLA HÍBRIDA]: 
           Este es el cálculo más importante del sistema. Aplica la función GREATEST().
           Fórmula: MAX(Inscritos_en_Sistema, Asistentes_Manuales).
           
           ¿Por qué?
           Si hay 5 inscritos en la BD, pero el Coordinador puso "20 Manuales" porque espera
           un grupo externo sin registro, el sistema debe considerar 20 asientos ocupados, no 5.
           Esto evita el "Overbooking" (Sobreventa) del aula. */
        `VC`.`Total_Impacto_Real`          AS `Total_de_Asistentes_Reales`, 

        /* [HISTÓRICO DE DESERCIÓN]:
           Conteo de participantes que estuvieron inscritos pero cambiaron a estatus "BAJA" (ID 5).
           Útil para medir la tasa de rotación o cancelación del curso. */
        `VC`.`Participantes_Baja`          AS `Total_de_Bajas`,

        /* [DISPONIBILIDAD FINAL]:
           El Delta matemático: (Meta - Impacto Real).
           Este valor es el que decide si se permiten nuevas inscripciones.
           Puede ser negativo si hubo sobrecupo autorizado. */
        `VC`.`Cupo_Disponible`,
        
        /* ------------------------------------------------------------------
           GRUPO E: ESTADO VISUAL
           Textos pre-calculados en la Vista para mostrar al usuario.
           ------------------------------------------------------------------ */
		`VC`.`Id_Estatus_Capacitacion`	   AS `Id_Estatus`, -- Mapeo numérico (4=Fin, 8=Canc, etc)
        `VC`.`Estatus_Curso`               AS `Estatus_Texto`, -- (ej: "FINALIZADO", "CANCELADO")

        `VC`.`Observaciones`               AS `Bitacora_Notas`,           -- Justificación de esta versión

        /* ------------------------------------------------------------------
           GRUPO F: BANDERAS LÓGICAS (LOGIC FLAGS - CRITICAL)
           Aquí reside la inteligencia arquitectónica. Entregamos el estado físico puro.
           Laravel usará esto para: if (Estatus_Del_Registro == 1 && User->isAdmin()) { ... }
           ------------------------------------------------------------------ */
        `Cap`.`Activo`                     AS `Estatus_Del_Registro`, -- 1 = Expediente Vivo / 0 = Archivado (Soft Delete)
		
        `VC`.`Estatus_del_Detalle`,
        
        `VC`.`CreadoElDia`,
        
        `VC`.`CreadoPor`,
        
        `VC`. `CreadoPor_Ficha`,
        
        `VC`.`CreadoPor_Nombre`,
        
        `VC`.`ActualzadoElDia`,
                
        `VC`.`ActualizadoPor`,
        
        `VC`.`ActualizadoPor_Ficha`,

		`VC`. `ActualizadoPor_Nombre`

    /* ============================================================================================
       FASE 2: ORIGEN DE DATOS Y RELACIONES (RELATIONAL ASSEMBLY)
       Objetivo: Construir el objeto de datos uniendo las entidades normalizadas.
       ============================================================================================ */
       
    FROM `PICADE`.`Vista_Capacitaciones` `VC`
    
    /* [JOIN 1 - JERARQUÍA PADRE]: Conexión con el Expediente Maestro (`Capacitaciones`).
       Necesario para conocer el estatus global (`Activo`) y la Gerencia dueña del proceso. */
    INNER JOIN `PICADE`.`Capacitaciones` `Cap` 
        ON `VC`.`Id_Capacitacion` = `Cap`.`Id_Capacitacion`

    /* [JOIN 2 - FILTRO DE ACTUALIDAD]: "MAX ID SNAPSHOT STRATEGY"
       ------------------------------------------------------------------------------------
       PROBLEMA: La tabla `DatosCapacitaciones` es un log histórico. Un curso puede tener 
       10 versiones (cambios de fecha, instructor, etc).
       
       SOLUCIÓN: Hacemos un JOIN contra una subconsulta que obtiene SOLO el ID más alto (MAX)
       agrupado por curso. Esto actúa como un filtro natural que descarta automáticamente 
       todo el historial obsoleto, dejando solo la "Foto Final".
       ------------------------------------------------------------------------------------ */
    /*INNER JOIN (
        SELECT Id_DatosCap, Activo 
        FROM `PICADE`.`DatosCapacitaciones`
        WHERE Id_DatosCap IN (
            SELECT MAX(Id_DatosCap) 
            FROM `PICADE`.`DatosCapacitaciones` 
            GROUP BY Fk_Id_Capacitacion
        )
    ) `Latest_Row` ON `VC`.`Id_Detalle_de_Capacitacion` = `Latest_Row`.`Id_DatosCap`*/

    /* ============================================================================================
       FASE 3: MOTOR DE FILTRADO (FILTERING ENGINE)
       Objetivo: Aplicar las reglas de negocio solicitadas por el usuario desde el Dashboard.
       ============================================================================================ */
    WHERE 

		/* 3.0 FILTRO DE ACTUALIDAD (Reemplazo de la subconsulta MAX)
           Exige que el detalle operativo de la vista sea la versión vigente. */
        `VC`.`Estatus_del_Detalle` = 1

        AND

        /* 3.1 FILTRO ORGANIZACIONAL (JERÁRQUICO)
           Lógica: Si `_Id_Gerencia` es 0 o NULL, la condición se vuelve TRUE globalmente, 
           mostrando todos los registros (Modo Director). Si tiene valor, filtra exacto. */
        -- (_Id_Gerencia IS NULL OR _Id_Gerencia <= 0 OR `Cap`.`Fk_Id_CatGeren` = _Id_Gerencia)
		(_Id_Gerencia IS NULL OR _Id_Gerencia <= 0 OR VC.Id_Gerencia = _Id_Gerencia)
        
        AND 
        
        /* 3.2 FILTRO DE RANGO TEMPORAL (CRONOLÓGICO)
           Lógica: Filtra estrictamente por la fecha de inicio.
           Nota: Laravel ya calculó las fechas exactas (Trimestre, Semestre, Año) antes de llamar. */
        (`VC`.`Fecha_Inicio` BETWEEN _Fecha_Min AND _Fecha_Max)

    /* ============================================================================================
       FASE 4: ORDENAMIENTO Y PRESENTACIÓN (UX SORTING)
       Objetivo: Definir el orden visual inicial para optimizar la lectura del usuario.
       ============================================================================================ */
    /* Regla UX: "Lo urgente primero". Ordenamos descendente por fecha para que los cursos
       más recientes o futuros aparezcan en la parte superior de la tabla. */
    ORDER BY `VC`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;
