/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_ConsularMisCursos
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial       : SP_ConsularMisCursos
   - Sistema:             : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Clasificación        : Consulta de Historial Académico Personal (Student Record Inquiry)
   - Patrón de Diseño     : Latest Snapshot Filtering (Filtro de Última Versión)
   - Nivel de Aislamiento : READ COMMITTED
   - Dependencia Core     : Vista_Gestion_de_Participantes

   II. PROPÓSITO Y LÓGICA DE NEGOCIO (BUSINESS VALUE)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento alimenta el Dashboard del Participante. Su objetivo es mostrar el "Estado del Arte"
   de su capacitación. 
   
   [REGLA DE UNICIDAD]: 
   Si un curso (Folio) ha tenido varias versiones operativas (Reprogramaciones o Archivos), el sistema 
   debe mostrar solo la instancia más reciente donde el alumno estuvo inscrito. Esto previene la 
   confusión de ver "3 veces el mismo curso" en el historial.

   [REGLA DE VISIBILIDAD TOTAL]:
   A diferencia de los administradores que filtran por "Activo=1", el alumno debe ver sus cursos 
   FINALIZADOS y ARCHIVADOS, ya que forman parte de su currículum institucional y evidencia de formación.

   III. ARQUITECTURA DE FILTRADO (QUERY STRATEGY)
   ----------------------------------------------------------------------------------------------------------
   Se utiliza una subconsulta correlacionada con la función MAX(Id_Detalle_de_Capacitacion). 
   Esta estrategia garantiza que, de N registros para el mismo Folio y mismo Usuario, solo emerja 
   hacia el Frontend el registro con el ID más alto, que cronológicamente representa el último estado.

   ========================================================================================================== */

DELIMITER $$

 DROP PROCEDURE IF EXISTS `SP_ConsularMisCursos`$$

CREATE PROCEDURE `SP_ConsularMisCursos`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IN _Id_Usuario INT -- Identificador del participante autenticado en la sesión.
)
ProcMisCursos: BEGIN
    
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN DE ENTRADA
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IF _Id_Usuario IS NULL OR _Id_Usuario <= 0 
		THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario es obligatorio para la consulta.' AS Mensaje, 
               'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcMisCursos;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CONSULTA DE HISTORIAL UNIFICADO (THE TRUTH ENGINE)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
		-- [BLOQUE 1: IDENTIFICADORES DE NAVEGACIÓN]
		-- Identificadores de Navegación (Handles)

        `VGP`.`Id_Registro_Participante`,      -- PK de la relación Alumno-Curso.
        `VGP`.`Id_Capacitacion`,               -- [CORREGIDO]: ID de la tabla maestra (Padre).
        `VGP`.`Id_Detalle_de_Capacitacion`,    -- ID de la instancia operativa específica (Hijo).
        
		-- GRUPO B: DATOS VISUALES
        `VGP`.`Folio`,                   -- Referencia institucional (Numero_Capacitacion).
        
        /* [Gerencia]: Centro de Costos o Área dueña del presupuesto del curso. */
		`VGP`.`Id_Subdireccion`,
        `VGP`.`Clave_Subdireccion`,
        `VGP`.`Nombre_Subdireccion`,
        
        `VGP`.`Id_Gerencia`,
        `VGP`.`Gerencia`,
        `VGP`.`Nombre_Gerencia`,

		-- [BLOQUE 2: METADATA DEL CONTENIDO]
        -- Metadatos del Contenido (Course Context)
		`VGP`.`Id_Tema`,
        `VGP`.`Codigo_Tema`,
        `VGP`.`Tema`,      -- Materia Académica Título del tema impartido.
        `VGP`.`Descripcion_Tema`,
        
        /* [Duración]: Carga horaria académica.
           [IMPORTANCIA LEGAL]: Dato obligatorio para la generación de formatos DC-3 ante la STPS.
           Sin este dato, la constancia no tiene validez oficial.*/
        `VGP`.`Tipo_Instruccion`,
        `VGP`.`Duracion`, -- Valor curricular para el instructor. Carga horaria oficial.
        
        /* [Instructor]: Nombre ya concatenado y procesado por la vista madre.
           Optimiza el rendimiento al evitar concatenaciones repetitivas en tiempo de ejecución.*/
		-- El instructor es él mismo, pero enviamos los datos para consistencia del objeto
		`VGP`.`Id_Instructor`,
        `VGP`.`Ficha_Instructor`,
        `VGP`.`Instructor`,	-- Quién impartió la capacitación.
          
        /* [Sede]: Ubicación física (Aula) o virtual (Teams/Zoom). Alias singularizado. */
        -- [BLOQUE 3: LOGÍSTICA DE OPERACIÓN]
        `VGP`.`Id_Sedes`,
        `VGP`.`Codigo_Sede`,
        `VGP`.`Sede`,          -- Ubicación del evento. Ubicación física o lógica.
        
        /* [Modalidad]: Método de entrega (Presencial, En Línea, Mixto). */
        `VGP`.`Id_Modalidad`,
        `VGP`.`Modalidad`, -- Método de entrega. Método de impartición.
        
		-- GRUPO C: METADATOS TEMPORALES
		/* [Fechas]: Ventana de tiempo de ejecución.
           CRÍTICO: Estas fechas vienen del DETALLE, no de la cabecera. Son las reales.*/
        `VGP`.`Fecha_Inicio`,	-- Apertura del curso.
        `VGP`.`Fecha_Fin`,		-- Cierre del curso.
        YEAR(`VGP`.`Fecha_Inicio`)          AS `Anio`,
        MONTHNAME(`VGP`.`Fecha_Inicio`)     AS `Mes`,

		/* -----------------------------------------------------------------------------------
           BLOQUE 6: CONTROL DE ESTADO Y CICLO DE VIDA
           Textos pre-calculados en la Vista para mostrar al usuario.
           El corazón del flujo de trabajo. Determina si el curso está vivo, muerto o finalizado.
           ----------------------------------------------------------------------------------- */
		`VGP`.`Id_Estatus`, -- Mapeo numérico (4=Fin, 8=Canc, etc) Útil para lógica de colores en UI (ej: CANC = Rojo) CRÍTICO: ID necesario para el match() en Blade
        `VGP`.`Codigo_Estatus_Capacitacion`,
        `VGP`.`Estatus_Curso_Capacitacion`, -- (ej: "FINALIZADO", "CANCELADO") Estado operativo (En curso, Finalizado, etc). Estado de la capacitación (FINALIZADO, ARCHIVADO, etc.).

        /* -----------------------------------------------------------------------------------------
           [INFORMACIÓN VISUAL DEL PARTICIPANTE]
           Datos para que el humano identifique al alumno.
           ----------------------------------------------------------------------------------------- */
        -- ID Corporativo o Número de Empleado. Vital para diferenciar homónimos.
		/* [Ficha]: ID único corporativo del empleado. Clave de búsqueda principal. */
        `VGP`.`Id_Participante`,
        `VGP`.`Ficha_Participante`,  
        /* Componentes del nombre desglosados para ordenamiento (Sorting) en tablas */
        `VGP`.`Nombre_Participante`, -- Hereda el CONCAT_WS de la raíz

        /* =================================================================================
           SECCIÓN D: EVALUACIÓN Y RESULTADOS (LA SÁBANA DE CALIFICACIONES)
           Objetivo: Exponer los KPIs de rendimiento del alumno en este curso específico.
           Origen: Tabla de Hechos `Capacitaciones_Participantes` y Catálogo de Estatus.
           ================================================================================= */ 
        /* [Asistencia]: KPI de Cumplimiento.
           Porcentaje de sesiones asistidas. Vital para reglas de aprobación automática.*/
        `VGP`.`Asistencia`, -- % de presencia física.

        /* [Calificación]: Valor Cuantitativo (Numérico).
           El dato crudo de la nota obtenida (0 a 100).*/
        `VGP`.`Calificacion`,  -- Nota decimal asentada.
        
        /* NUEVA COLUMNA EXPUESTA */
        `VGP`.`Justificacion`, -- Inyección forense de por qué hubo cambios.
        
        /* [Resultado Final]: Valor Semántico (Texto).
           Ejemplos: "APROBADO", "REPROBADO", "NO SE PRESENTÓ".
           Útil para etiquetas de colores (Badges) en el UI
        -- Estatus Semántico (Texto).
        -- Valores posibles: 'INSCRITO', 'ASISTIÓ', 'APROBADO', 'REPROBADO', 'BAJA'.
        -- Se usa para determinar el color de la fila (ej: Baja = Rojo, Aprobado = Verde).*/      
        `VGP`.`Id_Estatus_Participante`,
		`VGP`.`Codigo_Estatus_Participante`,
        `VGP`.`Nombre_Estatus_Participante`,       
        
        /* [Detalle]: Descripción técnica de la regla de negocio aplicada (ej: "Calif < 80"). */
		-- Descripción Técnica.
        -- Explica la regla de negocio aplicada (ej: "Reprobado por inasistencia > 20%").
        -- Se usa típicamente en un Tooltip al pasar el mouse sobre el estatus.
        `VGP`.`Descripcion_Estatus_Participante`,
        
		/* =================================================================================
           SECCIÓN E: AUDITORÍA FORENSE (Trazabilidad del Dato)
           Objetivo: Responder ¿Quién? y ¿Cuándo?
           ================================================================================= */
		/* --- SECCIÓN E: AUDITORÍA (Simplificada con Vista_Usuarios) --- */
		-- 1. CREACIÓN (Inscripción Original)
		`VGP`.`Fecha_Inscripcion`, -- Cuándo se unió el alumno.
        `VGP`.`Inscrito_Por`,
        
		-- 2. MODIFICACIÓN (Último cambio de nota o estatus) 
        `VGP`.`Fecha_Ultima_Modificacion`, -- Última vez que se tocó el registro.
        `VGP`.`Modificado_Por`

    FROM `PICADE`.`Vista_Gestion_de_Participantes` `VGP`
    
    -- Filtro mandatorio por usuario solicitante
    WHERE `VGP`.`Id_Participante` = _Id_Usuario
    --     WHERE `VGP`.`Ficha_Participante` = (SELECT `Ficha_Usuario` FROM `Vista_Usuarios` WHERE `Id_Usuario` = _Id_Usuario)
    
    /* ------------------------------------------------------------------------------------------------------
       LÓGICA SNAPSHOT (FILTRO ANTI-DUPLICADOS)
       Este AND asegura que si el Folio 'CAP-001' aparece 3 veces en la tabla por reprogramaciones,
       solo el ID de detalle más reciente sea seleccionado.
       ------------------------------------------------------------------------------------------------------ */
    /*AND `VGP`.`Id_Detalle_de_Capacitacion` = (
        SELECT MAX(`VSub`.`Id_Detalle_de_Capacitacion`)
        FROM `PICADE`.`Vista_Gestion_de_Participantes` `VSub`
        WHERE `VSub`.`Folio_Curso` = `VGP`.`Folio_Curso`
          AND `VSub`.`Ficha_Participante` = `VGP`.`Ficha_Participante`
    )*/
    
	/* ------------------------------------------------------------------------------------------------------
       LÓGICA SNAPSHOT (FILTRO ANTI-DUPLICADOS)
       ------------------------------------------------------------------------------------------------------ */
    AND `VGP`.`Id_Detalle_de_Capacitacion` = (
        SELECT MAX(`VSub`.`Id_Detalle_de_Capacitacion`)
        FROM `PICADE`.`Vista_Gestion_de_Participantes` `VSub`
        WHERE `VSub`.`Id_Capacitacion` = `VGP`.`Id_Capacitacion` -- ✅ Agrupando por ID Padre (Rápido y Seguro)
          AND `VSub`.`Id_Participante` = `VGP`.`Id_Participante`
    )
    
    -- Ordenamiento cronológico inverso (Lo más nuevo al principio del Dashboard)
    ORDER BY `VGP`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;