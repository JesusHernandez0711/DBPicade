/* ======================================================================================================
   VIEW: Vista_Capacitaciones
   ======================================================================================================
   
   1. OBJETIVO TÉCNICO Y DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------------------
   Esta vista implementa el patrón de diseño "Flattened Master-Detail" (Maestro-Detalle Aplanado).
   Su función es unificar la estructura transaccional dividida del sistema:
     - Cabecera Administrativa (`Capacitaciones`): Datos inmutables como Folio y Gerencia.
     - Detalle Operativo (`DatosCapacitaciones`): Datos mutables como Fechas, Instructor y Estatus.

   [PROPÓSITO ESTRATÉGICO]:
   Actúa como la fuente de verdad única para:
   - El Grid Principal de Gestión de Cursos (Dashboard del Coordinador).
   - Generación de Reportes de Cumplimiento (Auditoría).
   - Validaciones de cruce de horarios (Detección de conflictos).
   
   Al consumir esta vista, el Frontend y los servicios de reporte se abstraen de la complejidad 
   de los 8 JOINs subyacentes, recibiendo una estructura de datos limpia y semántica.

   2. ARQUITECTURA DE INTEGRACIÓN (LAYERED ARCHITECTURE)
   -----------------------------------------------------
   Esta vista no consulta tablas crudas (Raw Tables) indiscriminadamente. Aplica una arquitectura 
   de capas consumiendo OTRAS VISTAS (`Vista_Usuarios`, `Vista_Organizacion`, etc.) cuando es posible.
   
   [BENEFICIOS DE ESTA ARQUITECTURA]:
   - Encapsulamiento: Si cambia la lógica de cómo se calcula el nombre completo de un usuario en 
     `Vista_Usuarios`, esta vista lo hereda automáticamente sin re-codificar.
   - Consistencia: Garantiza que el nombre de la Sede se vea igual en el módulo de Sedes y en el de Cursos.

   3. DICCIONARIO DE DATOS (OUTPUT CONTRACT)
   -----------------------------------------
   [Bloque 1: Identidad del Curso]
   - Id_Capacitacion:      (INT) PK de la Cabecera.
   - Numero_Capacitacion:  (VARCHAR) El Folio único (ej: 'CAP-2026-001').
   
   [Bloque 2: Contexto Administrativo]
   - Clave_Gerencia:       (VARCHAR) Quién solicitó/paga el curso.
   - Codigo_Tema:          (VARCHAR) Identificador académico.
   - Nombre_Tema:          (VARCHAR) Título del curso.
   - Tipo_Instruccion:     (VARCHAR) Naturaleza (Teórico/Práctico).
   - Duracion_Horas:       (INT) Carga horaria académica.
   
   [Bloque 3: Factor Humano (Instructor)]
   - Ficha_Instructor:     (VARCHAR) ID corporativo del instructor.
   - Nombre_Instructor:    (VARCHAR) Nombre completo concatenado (Nombre + Apellidos).
   
   [Bloque 4: Logística y Ejecución]
   - Fecha_Inicio/Fin:     (DATE) Ventana de tiempo de ejecución.
   - Sede:                 (VARCHAR) Ubicación física o virtual.
   - Modalidad:            (VARCHAR) Presencial/En Línea/Mixta.
   
   [Bloque 5: Métricas y Estado]
   - Estatus_Curso:        (VARCHAR) Estado actual del flujo (Programado, Finalizado, Cancelado).
   - Asistentes_Meta:      (INT) Cupo planeado (KPI).
   - Asistentes_Reales:    (INT) Cupo logrado (KPI).
   - Observaciones:        (TEXT) Notas de bitácora.
   - Registro_Activo:      (BOOL) Soft Delete flag del detalle operativo.
   ====================================================================================================== */

CREATE OR REPLACE 
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Capacitaciones` AS
    SELECT 
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD NUCLEAR (HEADER DATA)
           Datos provenientes de la tabla padre `Capacitaciones`. Son inmutables durante
           la ejecución del curso.
           ----------------------------------------------------------------------------------- */
        `Cap`.`Id_Capacitacion`             AS `Id_Capacitacion`,
        `DatCap`.`Id_DatosCap`				AS `Id_Detalle_de_Capacitacion`,
        `Cap`.`Numero_Capacitacion`         AS `Numero_Capacitacion`, -- El Folio (Key de Negocio)

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: CLASIFICACIÓN ORGANIZACIONAL Y ACADÉMICA
           Contexto de quién pide el curso y qué se va a enseñar.
           ----------------------------------------------------------------------------------- */
		`Org`.`Id_Subdireccion`, 
		`Org`.`Clave_Subdireccion`,
        `Org`.`Nombre_Subdireccion`,
        
        `Org`.`Id_Gerencia`,
        `Org`.`Clave_Gerencia`,
        `Org`.`Nombre_Gerencia`,
        
        `Tem`.`Id_Tema`,
        `Tem`.`Codigo_Tema`,
        `Tem`.`Nombre_Tema`,
        `Tem`.`Descripcion`					AS `Descripcion_Tema`,
        
        `Tem`.`Nombre_Tipo_Instruccion`     AS `Tipo_Instruccion`, -- Heredado de la vista de temas
        `Tem`.`Duracion_Horas`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: METAS DE ASISTENCIA (KPIs)
           Comparativa entre lo planeado (Cabecera) y lo real (Detalle).
           ----------------------------------------------------------------------------------- */
		/* --- BLOQUE 3: LÓGICA HÍBRIDA DE ASISTENCIA --- */
        `Cap`.`Asistentes_Programados`      AS `Asistentes_Meta`,
        `DatCap`.`AsistentesReales`         AS `Asistentes_Manuales`, -- Renombramos para claridad
        
        /* A) CONTADOR DE SISTEMA (Dinámico) */
        (SELECT COUNT(*) FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
         WHERE `CP`.`Fk_Id_DatosCap` = `DatCap`.`Id_DatosCap` AND `CP`.`Fk_Id_CatEstPart` != 5
        )                                   AS `Participantes_Activos`,

        /* B) CONTADOR DE BAJAS */
        (SELECT COUNT(*) FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
         WHERE `CP`.`Fk_Id_DatosCap` = `DatCap`.`Id_DatosCap` AND `CP`.`Fk_Id_CatEstPart` = 5
        )                                   AS `Participantes_Baja`,

        /* C) TOTAL IMPACTO REAL (LA REGLA DEL MÁXIMO) 🧠 
           Compara el dato manual vs el dato de sistema y se queda con el mayor.
           Esto resuelve tu problema de los "27 asistentes". */
        GREATEST(
            COALESCE(`DatCap`.`AsistentesReales`, 0), 
            (SELECT COUNT(*) FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
             WHERE `CP`.`Fk_Id_DatosCap` = `DatCap`.`Id_DatosCap` AND `CP`.`Fk_Id_CatEstPart` != 5)
        )                                   AS `Total_Impacto_Real`,

        /* D) CUPO DISPONIBLE (Usando el Impacto Real para mayor precisión) */
        (
            `Cap`.`Asistentes_Programados` - 
            GREATEST(
                COALESCE(`DatCap`.`AsistentesReales`, 0), 
                (SELECT COUNT(*) FROM `PICADE`.`Capacitaciones_Participantes` `CP` 
                 WHERE `CP`.`Fk_Id_DatosCap` = `DatCap`.`Id_DatosCap` AND `CP`.`Fk_Id_CatEstPart` != 5)
            )
        )                                   AS `Cupo_Disponible`,
        
        /* -----------------------------------------------------------------------------------
           BLOQUE 4: PERSONAL DOCENTE (INSTRUCTOR)
           Datos del instructor asignado en el detalle operativo actual.
           Se concatena el nombre para facilitar la visualización en reportes.
           ----------------------------------------------------------------------------------- */
		`Us`.`Id_Usuario`					AS `Id_Instructor`,
        `Us`.`Ficha_Usuario`                AS `Ficha_Instructor`,
        `Us`.`Nombre_Completo`				AS `Nombre_Instructor`,
        
        /* -----------------------------------------------------------------------------------
           BLOQUE 5: LOGÍSTICA TEMPORAL Y ESPACIAL (OPERACIÓN)
           Datos críticos para el calendario y la logística.
           ----------------------------------------------------------------------------------- */
        `DatCap`.`Fecha_Inicio`,
        `DatCap`.`Fecha_Fin`,
        
        `Sede`.`Id_Sedes`,
        `Sede`.`Codigo_Sedes`               AS `Codigo_Sede`,
        `Sede`.`Nombre_Sedes`               AS `Nombre_Sede`,
        
        `Moda`.`Id_Modalidad`,
        `Moda`.`Codigo_Modalidad`,
        `Moda`.`Nombre_Modalidad`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 6: CONTROL DE ESTADO Y CICLO DE VIDA
           El corazón del flujo de trabajo. Determina si el curso está vivo, muerto o finalizado.
           ----------------------------------------------------------------------------------- */
		`EstCap`.`Id_Estatus_Capacitacion`		AS `Id_Estatus`, -- Mapeo numérico (4=Fin, 8=Canc, etc) Útil para lógica de colores en UI (ej: CANC = Rojo) CRÍTICO: ID necesario para el match() en Blade
        `EstCap`.`Codigo_Estatus`           AS `Codigo_Estatus_Capacitacion`, -- Útil para lógica de colores en UI (ej: CANC = Rojo)
        `EstCap`.`Nombre_Estatus`           AS `Estatus_Curso_Capacitacion`,
        
        `DatCap`.`Observaciones`,
        
        /* Bandera de Soft Delete del DETALLE operativo. 
           Nota: La cabecera también tiene 'Activo', pero el detalle manda en la operación diaria. */
        `DatCap`.`Activo`                   AS `Estatus_del_Detalle`,
        
        `Cap`.`created_at` AS `CreadoElDia`,
        
        `Cap`.`Fk_Id_Usuario_Cap_Created_by` AS `CreadoPor`,
        
		/* Reutilizamos directamente tu Vista_Usuarios para Creador */
        `Creator_VU`.`Ficha_Usuario`                 AS `CreadoPor_Ficha`,  
        `Creator_VU`.`Nombre_Completo`               AS `CreadoPor_Nombre`,
        
        `DatCap`.`updated_at` AS `ActualzadoElDia`,
                
        `DatCap`.`Fk_Id_Usuario_DatosCap_Updated_by` AS `ActualizadoPor`,

        /* Reutilizamos directamente tu Vista_Usuarios para Editor */
        `Editor_VU`.`Ficha_Usuario`                  AS `ActualizadoPor_Ficha`, 
        `Editor_VU`.`Nombre_Completo`                AS `ActualizadoPor_Nombre`

    FROM
        /* -----------------------------------------------------------------------------------
           ESTRATEGIA DE JOINs (INTEGRITY MAPPING)
           Se utiliza INNER JOIN para las relaciones obligatorias fuertes y LEFT JOIN 
           (aunque en tu diseño parece que todo es obligatorio, usamos INNER para consistencia 
           con tu query aprobado) para asegurar la integridad referencial.
           ----------------------------------------------------------------------------------- */
        
        /* 1. EL PADRE (Cabecera) */
        `PICADE`.`Capacitaciones` `Cap`
        
        /* 2. EL HIJO (Detalle Operativo) - Relación 1:1 en el contexto de un reporte plano */
        JOIN `PICADE`.`DatosCapacitaciones` `DatCap` 
            ON `Cap`.`Id_Capacitacion` = `DatCap`.`Fk_Id_Capacitacion`
        
        /* 3. INSTRUCTOR (Consumiendo Vista de Usuarios) */
        JOIN `PICADE`.`Vista_Usuarios` `Us` 
            ON `DatCap`.`Fk_Id_Instructor` = `Us`.`Id_Usuario`
        
        /* 4. ORGANIZACIÓN (Consumiendo Vista Organizacional) */
        JOIN `PICADE`.`Vista_Organizacion` `Org` 
            ON `Cap`.`Fk_Id_CatGeren` = `Org`.`Id_Gerencia`
        
        /* 5. TEMA (Consumiendo Vista Académica) */
        JOIN `PICADE`.`Vista_Temas_Capacitacion` `Tem` 
            ON `Cap`.`Fk_Id_Cat_TemasCap` = `Tem`.`Id_Tema`
        
        /* 6. SEDE (Consumiendo Vista de Infraestructura) */
        JOIN `PICADE`.`Vista_Sedes` `Sede` 
            ON `DatCap`.`Fk_Id_CatCases_Sedes` = `Sede`.`Id_Sedes`
        
        /* 7. MODALIDAD (Consumiendo Vista de Modalidad) */
        JOIN `PICADE`.`Vista_Modalidad_Capacitacion` `Moda` 
            ON `DatCap`.`Fk_Id_CatModalCap` = `Moda`.`Id_Modalidad`
        
        /* 8. ESTATUS (Consumiendo Vista de Ciclo de Vida) */
        JOIN `PICADE`.`Vista_Estatus_Capacitacion` `EstCap` 
            ON `DatCap`.`Fk_Id_CatEstCap` = `EstCap`.`Id_Estatus_Capacitacion`
		/* -----------------------------------------------------------------------------------
           NUEVOS JOINS DE AUDITORÍA (LEFT JOINS PARA NO PERDER DATOS)
           ----------------------------------------------------------------------------------- */
		/* -----------------------------------------------------------------------------------
           NUEVOS JOINS DE AUDITORÍA (CONSUMIENDO TU VISTA_USUARIOS)
           ----------------------------------------------------------------------------------- */
        /* 9. CREADOR ORIGINAL */
        LEFT JOIN `PICADE`.`Vista_Usuarios` `Creator_VU` 
            ON `Cap`.`Fk_Id_Usuario_Cap_Created_by` = `Creator_VU`.`Id_Usuario`

        /* 10. ÚLTIMO EDITOR */
        LEFT JOIN `PICADE`.`Vista_Usuarios` `Editor_VU` 
            ON `DatCap`.`Fk_Id_Usuario_DatosCap_Updated_by` = `Editor_VU`.`Id_Usuario`;


/* --- VERIFICACIÓN DE LA VISTA (QA RÁPIDO) --- */
-- SELECT * FROM Picade.Vista_Capacitaciones LIMIT 10;