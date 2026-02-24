/* ======================================================================================================
   VISTA: Vista_Gestion_de_Participantes
   ======================================================================================================
   
   1. RESUMEN EJECUTIVO (EXECUTIVE SUMMARY)
   ----------------------------------------
   Esta vista constituye el "Motor de Inteligencia de Asistencia". Es el artefacto de base de datos
   que consolida la relación N:M (Muchos a Muchos) entre los Cursos y los Usuarios.
   
   [PROPÓSITO DE NEGOCIO]:
   Proporcionar al Coordinador de Capacitación una visión quirúrgica de lo que sucedió DENTRO
   de un curso específico. No mira al curso desde fuera (administrativo), sino desde dentro (operativo).
   
   2. ALCANCE FUNCIONAL (FUNCTIONAL SCOPE)
   ---------------------------------------
   - Fuente de Verdad para Grid de Asistentes: Alimenta la tabla donde se pasa lista.
   - Generador de Constancias DC-3: Provee los 3 datos legales requeridos (Nombre Exacto, Curso, Horas).
   - Auditoría de Calidad: Permite filtrar rápidamente índices de reprobación.

   3. ARQUITECTURA TÉCNICA (TECHNICAL ARCHITECTURE)
   ------------------------------------------------
   [PATRÓN DE DISEÑO]: "Denormalized Fact View" (Vista de Hechos Desnormalizada).
   [ESTRATEGIA DE ENLACE]: 
     Utiliza una vinculación estricta al nivel de DETALLE (`Id_Detalle_de_Capacitacion`).
     Esto garantiza la "Integridad Histórica": Si un curso se reprogramó 3 veces, 
     esta vista sabe exactamente a qué fecha asistió el usuario, evitando ambigüedad temporal.

   4. DEPENDENCIAS DE SISTEMA (SYSTEM DEPENDENCIES)
   ------------------------------------------------
   1. `Capacitaciones_Participantes` (Core Fact Table): La tabla física de relaciones.
   2. `Vista_Capacitaciones` (Master View): Contexto del evento.
   3. `Vista_Usuarios` (Identity Provider): Contexto de la persona.
   4. `Vista_Estatus_Participante` (Semantics): Contexto del resultado.
   ====================================================================================================== */

CREATE OR REPLACE 
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Gestion_de_Participantes` AS
    SELECT 
        /* =================================================================================
           SECCIÓN A: IDENTIDAD TRANSACCIONAL (PRIMARY KEYS & HANDLES)
           Objetivo: Proveer identificadores únicos para operaciones CRUD en el Frontend.
           ================================================================================= */
        
        /* [CAMPO]: Id_Registro_Participante
           [ORIGEN]: Tabla `Capacitaciones_Participantes`.`Id_CapPart` (PK)
           [DESCRIPCIÓN TÉCNICA]: Llave Primaria del registro de inscripción.
           [USO EN FRONTEND]: Es el valor oculto que se envía al servidor cuando el Coordinador
           hace clic en "Editar Calificación" o "Eliminar Alumno". Sin esto, el sistema es ciego.
        */
        
        `Rel`.`Id_CapPart`                  AS `Id_Registro_Participante`, 

        /* [CAMPO]: Folio_Curso
           [ORIGEN]: Tabla `Capacitaciones`.`Numero_Capacitacion` (Vía Vista Madre)
           [DESCRIPCIÓN TÉCNICA]: Identificador Humano-Legible (Business Key).
           [USO EN FRONTEND]: Permite al usuario confirmar visualmente que está editando
           el curso correcto (ej: "CAP-2026-001").
        */
        -- [CORRECCIÓN CRÍTICA]: Agregamos el ID del Padre que faltaba
        `VC`.`Id_Capacitacion`,
		`VC`.`Id_Detalle_de_Capacitacion`,
        
        -- GRUPO B: DATOS VISUALES
        `VC`.`Numero_Capacitacion`         AS `Folio`, -- Identificador institucional.

        /* =================================================================================
           SECCIÓN B: CONTEXTO DEL CURSO (HERENCIA DE VISTA MADRE)
           Objetivo: Contextualizar la inscripción con datos del evento formativo.
           Nota: Estos datos son de SOLO LECTURA en esta vista.
           ================================================================================= */
        
        /* [Gerencia]: Centro de Costos o Área dueña del presupuesto del curso. */
		`VC`.`Id_Subdireccion`,
        `VC`.`Clave_Subdireccion`,
        `VC`.`Nombre_Subdireccion`,
        
        `VC`.`Id_Gerencia`,
        `VC`.`Clave_Gerencia`  AS `Gerencia`,
        `VC`.`Nombre_Gerencia`,
        
        /* [Tema]: El contenido académico impartido (Nombre de la materia). */
        `VC`.`Id_Tema`,
        `VC`.`Codigo_Tema`,
        `VC`.`Nombre_Tema`                 AS `Tema`, -- Contenido impartido.
        `VC`.`Descripcion_Tema`,
                
        /* [Duración]: Carga horaria académica.
           [IMPORTANCIA LEGAL]: Dato obligatorio para la generación de formatos DC-3 ante la STPS.
           Sin este dato, la constancia no tiene validez oficial.*/
        `VC`.`Tipo_Instruccion`,
        `VC`.`Duracion_Horas`              AS `Duracion`, -- Valor curricular para el instructor.
        
        /* [Instructor]: Nombre ya concatenado y procesado por la vista madre.
           Optimiza el rendimiento al evitar concatenaciones repetitivas en tiempo de ejecución.*/
		-- El instructor es él mismo, pero enviamos los datos para consistencia del objeto
		`VC`.`Id_Instructor`,
        `VC`.`Ficha_Instructor`,
        `VC`.`Nombre_Instructor`			AS `Instructor`,
        
        /* [Sede]: Ubicación física (Aula) o virtual (Teams/Zoom). Alias singularizado. */
        -- [BLOQUE 3: LOGÍSTICA DE OPERACIÓN]
        `VC`.`Id_Sedes`,
        `VC`.`Codigo_Sede`,
        `VC`.`Nombre_Sede` AS `Sede`,          -- Ubicación del evento.

        /* [Modalidad]: Método de entrega (Presencial, En Línea, Mixto). */
        `VC`.`Id_Modalidad`,
        `VC`.`Nombre_Modalidad` AS `Modalidad`, -- Método de entrega.
        
		-- GRUPO C: METADATOS TEMPORALES
		/* [Fechas]: Ventana de tiempo de ejecución.
           CRÍTICO: Estas fechas vienen del DETALLE, no de la cabecera. Son las reales.*/
        `VC`.`Fecha_Inicio`,	-- Apertura del curso.
        `VC`.`Fecha_Fin`,		-- Cierre del curso.
        YEAR(`VC`.`Fecha_Inicio`)          AS `Anio`,
        MONTHNAME(`VC`.`Fecha_Inicio`)     AS `Mes`,
        
        /* [Estatus Global]: Estado del contenedor padre (ej: Si el curso está CANCELADO, esto lo indica). */
        /* ------------------------------------------------------------------
           GRUPO E: ESTADO VISUAL
           Textos pre-calculados en la Vista para mostrar al usuario.
           ------------------------------------------------------------------ */
		/* -----------------------------------------------------------------------------------
           BLOQUE 6: CONTROL DE ESTADO Y CICLO DE VIDA
           El corazón del flujo de trabajo. Determina si el curso está vivo, muerto o finalizado.
           ----------------------------------------------------------------------------------- */
		`VC`.`Id_Estatus`, -- Mapeo numérico (4=Fin, 8=Canc, etc) Útil para lógica de colores en UI (ej: CANC = Rojo) CRÍTICO: ID necesario para el match() en Blade
        `VC`.`Codigo_Estatus_Capacitacion`,
        `VC`.`Estatus_Curso_Capacitacion`, -- (ej: "FINALIZADO", "CANCELADO") Estado operativo (En curso, Finalizado, etc).
        
        /* [Estatus del Registro]: Bandera de Soft Delete (Activo=1 / Borrado=0).
           Heredado para saber si el curso sigue visible en el sistema.
        */
        -- [CORRECCIÓN DEL ERROR 1054]: 
        -- En Vista_Capacitaciones el campo se llama 'Estatus_del_Detalle'
		-- `VC`.`Estatus_del_Detalle`,
        `VC`.`Estatus_del_Detalle`          AS `Estatus_del_Registro`,

        /* =================================================================================
           SECCIÓN C: IDENTIDAD DEL PARTICIPANTE (PERFIL DEL ALUMNO)
           Objetivo: Identificar inequívocamente a la persona inscrita.
           Origen: `Vista_Usuarios` (Alias `UsPart`).
           ================================================================================= */
        /* [Ficha]: ID único corporativo del empleado. Clave de búsqueda principal. */
        `UsPart`.`Id_Usuario`				AS `Id_Participante`,
        `UsPart`.`Ficha_Usuario`            AS `Ficha_Participante`,  
        /* Componentes del nombre desglosados para ordenamiento (Sorting) en tablas */
        `UsPart`.`Nombre_Completo` 			AS `Nombre_Participante`, -- Hereda el CONCAT_WS de la raíz
        
        /* =================================================================================
           SECCIÓN D: EVALUACIÓN Y RESULTADOS (LA SÁBANA DE CALIFICACIONES)
           Objetivo: Exponer los KPIs de rendimiento del alumno en este curso específico.
           Origen: Tabla de Hechos `Capacitaciones_Participantes` y Catálogo de Estatus.
           ================================================================================= */ 

        /* [Asistencia]: KPI de Cumplimiento.
           Porcentaje de sesiones asistidas. Vital para reglas de aprobación automática.*/
        `Rel`.`PorcentajeAsistencia`        AS `Asistencia`, -- % de presencia física.

        /* [Calificación]: Valor Cuantitativo (Numérico).
           El dato crudo de la nota obtenida (0 a 100).*/
        `Rel`.`Calificacion`,  -- Nota decimal asentada.
        
        /* NUEVA COLUMNA EXPUESTA */
        `Rel`.`Justificacion`, -- Inyección forense de por qué hubo cambios.
        
        /* [Resultado Final]: Valor Semántico (Texto).
           Ejemplos: "APROBADO", "REPROBADO", "NO SE PRESENTÓ".
           Útil para etiquetas de colores (Badges) en el UI
        -- Estatus Semántico (Texto).
        -- Valores posibles: 'INSCRITO', 'ASISTIÓ', 'APROBADO', 'REPROBADO', 'BAJA'.
        -- Se usa para determinar el color de la fila (ej: Baja = Rojo, Aprobado = Verde).*/      
        `EstPart`.`Id_Estatus_Participante`,
		`EstPart`.`Codigo_Estatus` AS `Codigo_Estatus_Participante`,
        `EstPart`.`Nombre_Estatus` AS `Nombre_Estatus_Participante`,       
        
        /* [Detalle]: Descripción técnica de la regla de negocio aplicada (ej: "Calif < 80"). */
		-- Descripción Técnica.
        -- Explica la regla de negocio aplicada (ej: "Reprobado por inasistencia > 20%").
        -- Se usa típicamente en un Tooltip al pasar el mouse sobre el estatus.
        `EstPart`.`Descripcion_Estatus` AS `Descripcion_Estatus_Participante`,
        
		/* =================================================================================
           SECCIÓN E: AUDITORÍA FORENSE (Trazabilidad del Dato)
           Objetivo: Responder ¿Quién? y ¿Cuándo?
           ================================================================================= */
		/* --- SECCIÓN E: AUDITORÍA (Simplificada con Vista_Usuarios) --- */
		-- 1. CREACIÓN (Inscripción Original)
        `Rel`.`created_at`                  AS `Fecha_Inscripcion`,
        `UsCrea`.`Nombre_Completo`          AS `Inscrito_Por`,

        -- 2. MODIFICACIÓN (Último cambio de nota o estatus) 
        `Rel`.`updated_at`                  AS `Fecha_Ultima_Modificacion`,
        `UsMod`.`Nombre_Completo`           AS `Modificado_Por`
        
    FROM
        /* ---------------------------------------------------------------------------------
           CAPA 1: LA TABLA DE HECHOS (FACT TABLE)
           Es el núcleo de la vista. Contiene la relación física entre IDs.
           --------------------------------------------------------------------------------- */
        `PICADE`.`Capacitaciones_Participantes` `Rel`
        
        /* ---------------------------------------------------------------------------------
           CAPA 2: ENLACE AL CONTEXTO DEL CURSO (INNER JOIN)
           [LÓGICA FORENSE]: 
           Se une con `Vista_Capacitaciones` usando `Id_Detalle_de_Capacitacion`.
           
           ¿POR QUÉ NO USAR 'Id_Capacitacion'?
           Porque un mismo curso (Folio) puede tener múltiples instancias en el tiempo (reprogramaciones).
           Al unir por el ID del DETALLE, garantizamos que el alumno está ligado a la 
           ejecución específica (Fecha/Hora/Instructor) y no al concepto abstracto del curso.
           --------------------------------------------------------------------------------- */
		/* 2. CONTEXTO DEL CURSO (Hereda la inteligencia de auditoría y nombres) */
        INNER JOIN `PICADE`.`Vista_Capacitaciones` `VC`
            ON `Rel`.`Fk_Id_DatosCap` = `VC`.`Id_Detalle_de_Capacitacion`

        /* ---------------------------------------------------------------------------------
           CAPA 3: ENLACE A LA IDENTIDAD (INNER JOIN)
           Resolución del ID de Usuario (`Fk_Id_Usuario`) a datos legibles (Nombre, Ficha).
           --------------------------------------------------------------------------------- */
        /* 3. IDENTIDAD DEL ALUMNO */
        INNER JOIN `PICADE`.`Vista_Usuarios` `UsPart`
            ON `Rel`.`Fk_Id_Usuario` = `UsPart`.`Id_Usuario`
		
        /* ---------------------------------------------------------------------------------
           CAPA 4: ENLACE A LA SEMÁNTICA DE ESTATUS (INNER JOIN)
           Resolución del código de estatus (`Fk_Id_CatEstPart`) a texto de negocio.
           --------------------------------------------------------------------------------- */
        INNER JOIN `PICADE`.`Vista_Estatus_Participante` `EstPart`
            ON `Rel`.`Fk_Id_CatEstPart` = `EstPart`.`Id_Estatus_Participante`

		/*-- 4. Datos del Creador (UsCrea) - ¡ESTO FALTABA!
		/* 4. AUDITORÍA DE INSCRIPCIÓN (Consumiendo Vista de Usuarios) */
        LEFT JOIN `PICADE`.`Vista_Usuarios` `UsCrea`
            ON `Rel`.`Fk_Id_Usuario_Created_By` = `UsCrea`.`Id_Usuario`

        -- 5. Datos del Modificador (UsMod) - ¡ESTO FALTABA! 
        /* 5. AUDITORÍA DE CAMBIOS (Consumiendo Vista de Usuarios) */
        LEFT JOIN `PICADE`.`Vista_Usuarios` `UsMod`
            ON `Rel`.`Fk_Id_Usuario_Updated_By` = `UsMod`.`Id_Usuario`;

/* --- VERIFICACIÓN RÁPIDA --- */
-- SELECT * FROM Picade.Vista_Gestion_de_Participantes LIMIT 5;