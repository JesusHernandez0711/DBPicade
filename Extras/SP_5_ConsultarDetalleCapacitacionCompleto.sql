/* ====================================================================================================
   PROCEDIMIENTO: SP_ConsultarDetalleCapacitacionCompleto
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre: SP_ConsultarDetalleCapacitacionCompleto
   - Tipo: Consulta de Múltiples Conjuntos de Resultados (Multi-ResultSet Query)
   - Patrón de Diseño: "Master-Detail-History Aggregation" (Agregación Maestro-Detalle-Historia)
   - Nivel de Aislamiento: Read Committed
   - Dependencias: 
       * `Vista_Capacitaciones` (Capa de Presentación del Evento)
       * `Vista_Gestion_de_Participantes` (Capa de Presentación de Personas)
       * `DatosCapacitaciones` (Capa Física de Persistencia)
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento constituye el **"Panel de Control 360°"** para la gestión de un curso.
   Su propósito es eliminar la fragmentación de la información, permitiendo al Coordinador Académico
   responder tres preguntas fundamentales en una sola interacción visual (Single Screen Experience):
   
     A) EL PRESENTE (Situational Awareness): 
        "¿En qué estado se encuentra el curso HOY?"
        (Datos operativos, logísticos y financieros actuales).
     
     B) LOS ACTORES (Stakeholder Management): 
        "¿Quiénes son los alumnos inscritos y cuál es su rendimiento?"
        (Lista nominal con calificaciones y asistencia en tiempo real).
     
     C) EL PASADO (Forensic Audit Trail): 
        "¿Cómo ha evolucionado este curso desde su creación?"
        (Línea de tiempo completa de cambios: instructores anteriores, reprogramaciones, cambios de sede).

   3. ARQUITECTURA DE DATOS (MULTI-RESULTSET STRATEGY)
   ---------------------------------------------------
   Para optimizar el rendimiento de red (Network Latency) y reducir la carga transaccional en la BD,
   este SP empaqueta tres consultas lógicas independientes en un solo "Viaje de Ida y Vuelta" (Round-Trip).
   
   [RESULTSET 1: HEADER & CONTEXT] (Single Row)
      - Contenido: Datos inmutables (Identidad), Datos mutables (Logística) y Datos de Auditoría de la versión actual.
      - Uso UI: Renderizado del Encabezado, Tarjetas de KPI y precarga del Formulario de Edición.
   
   [RESULTSET 2: BODY & PARTICIPANTS] (Multiple Rows)
      - Contenido: Nómina de alumnos con nombre formateado oficialmente y métricas de desempeño.
      - Uso UI: Renderizado del Grid/Tabla principal de gestión.
   
   [RESULTSET 3: FOOTER & HISTORY LOG] (Multiple Rows)
      - Contenido: Bitácora cronológica inversa de todas las versiones del curso.
      - Uso UI: Renderizado del componente "Timeline de Cambios" o "Historial de Versiones".

   4. ESTRATEGIA DE INTEGRIDAD Y SEGURIDAD (DEFENSE IN DEPTH)
   ----------------------------------------------------------
   - [Validación Fail-Fast]: Rechazo inmediato de parámetros nulos o negativos.
   - [Descubrimiento Jerárquico]: El SP infiere automáticamente el "Padre" (Folio del Curso) a partir
     de cualquier "Hijo" (Versión del Detalle), garantizando que el historial siempre sea completo,
     sin importar qué versión específica se esté consultando.
   - [Inyección Forense]: Se enriquecen los datos crudos con nombres reales de los responsables (Usuarios),
     evitando mostrar IDs numéricos opacos en la interfaz de auditoría.

   ==================================================================================================== */

DELIMITER $$

-- Eliminamos la versión anterior para asegurar una compilación limpia y libre de conflictos.
DROP PROCEDURE IF EXISTS `SP_ConsultarDetalleCapacitacionCompleto`$$

CREATE PROCEDURE `SP_ConsultarDetalleCapacitacionCompleto`(
    IN _Id_Detalle_Capacitacion INT -- [OBLIGATORIO] ID único de la versión específica (`DatosCapacitaciones`) que se desea inspeccionar.
)
BEGIN
    /* ============================================================================================
       BLOQUE 0: VARIABLES DE ENTORNO
       Definición de contenedores para la lógica de descubrimiento jerárquico.
       ============================================================================================ */
    DECLARE v_Id_Padre_Capacitacion INT; -- Almacenará el ID del Folio (Carpeta Madre) para agrupar el historial.

    /* ============================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA Y DESCUBRIMIENTO JERÁRQUICO
       Objetivo: Asegurar la integridad de la petición y localizar el contexto global del curso.
       ============================================================================================ */
    
    /* 1.1 Validación Defensiva de Tipos */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador de la Capacitación es inválido.';
    END IF;

    /* 1.2 Descubrimiento del Padre (Parent Discovery) */
    /* Buscamos a qué "Carpeta" (Capacitacion) pertenece esta "Hoja" (DatosCapacitaciones). */
    SELECT `Fk_Id_Capacitacion` INTO v_Id_Padre_Capacitacion
    FROM `DatosCapacitaciones`
    WHERE `Id_DatosCap` = _Id_Detalle_Capacitacion
    LIMIT 1;

    /* 1.3 Verificación de Existencia (404 Not Found) */
    /* Si la variable sigue siendo NULL, significa que el ID no existe en la base de datos. */
    IF v_Id_Padre_Capacitacion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La capacitación solicitada no existe o fue eliminada.';
    END IF;

    /* ============================================================================================
       BLOQUE 2: GENERACIÓN DEL RESULTSET 1 (EL EXPEDIENTE MAESTRO - HEADER)
       Objetivo: Entregar el contexto operativo actual, preparado tanto para lectura como para edición.
       ============================================================================================ */
    SELECT 
        /* ----------------------------------------------------------------------------------------
           GRUPO A: DATOS DE IDENTIDAD (INMUTABLES)
           Estos datos definen "QUÉ" es el curso. Son inherentes al Folio y no cambian entre versiones.
           Uso: Renderizado de títulos y etiquetas estáticas.
           ---------------------------------------------------------------------------------------- */
        `VC`.`Id_Capacitacion`             AS `Id_Padre`,          -- ID del Contenedor Global
        `VC`.`Numero_Capacitacion`         AS `Folio`,             -- Llave de Negocio (Business Key)
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia_Texto`,    -- Cliente Interno
        `VC`.`Nombre_Tema`                 AS `Tema_Texto`,        -- Contenido Académico
        `VC`.`Tipo_Instruccion`            AS `Tipo_Texto`,        -- Clasificación Pedagógica
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado`,   -- KPI Financiero

        /* ----------------------------------------------------------------------------------------
           GRUPO B: DATOS DE CONFIGURACIÓN (MUTABLES - "ROBUST HYDRATION")
           Estos datos definen "CÓMO" se ejecuta el curso. Pueden cambiar en el tiempo.
           Se entregan en pares (ID + Texto) para garantizar la integridad del formulario de edición.
           ---------------------------------------------------------------------------------------- */
        `DC`.`Id_DatosCap`                 AS `Id_Detalle`, -- PK de esta versión específica
        
        -- [1] INSTRUCTOR: Responsable de la ejecución
        `DC`.`Fk_Id_Instructor`            AS `Id_Instructor_Selected`, -- Value para el Select
        `VC`.`Nombre_Completo_Instructor`  AS `Instructor_Texto`,       -- Label de seguridad
        
        -- [2] SEDE: Ubicación física
        `DC`.`Fk_Id_CatCases_Sedes`        AS `Id_Sede_Selected`,       -- Value para el Select
        `VC`.`Nombre_Sede`                 AS `Sede_Texto`,             -- Label de seguridad
        
        -- [3] MODALIDAD: Formato de entrega
        `DC`.`Fk_Id_CatModalCap`           AS `Id_Modalidad_Selected`,  -- Value para el Select
        `VC`.`Nombre_Modalidad`            AS `Modalidad_Texto`,        -- Label de seguridad
        
        -- [4] ESTATUS: Estado del flujo de trabajo
        `DC`.`Fk_Id_CatEstCap`             AS `Id_Estatus_Selected`,    -- Value para el Select
        `VC`.`Estatus_Curso`               AS `Estatus_Texto`,          -- Label de seguridad
        `VC`.`Codigo_Estatus`              AS `Codigo_Estatus_Global`,  -- Metadato para colores (Badge UI)

        /* ----------------------------------------------------------------------------------------
           GRUPO C: DATOS OPERATIVOS (INPUTS DIRECTOS)
           Valores escalares editables directamente en inputs de texto o fecha.
           ---------------------------------------------------------------------------------------- */
        `DC`.`Fecha_Inicio`,
        `DC`.`Fecha_Fin`,
        `DC`.`Observaciones`               AS `Bitacora_Notas`,           -- Justificación del cambio actual
        `DC`.`AsistentesReales`            AS `Asistentes_Reales_Manual`, -- Conteo manual (Legacy)
        `VC`.`Duracion_Horas`,                                            -- Carga horaria

        /* ----------------------------------------------------------------------------------------
           GRUPO D: AUDITORÍA FORENSE DE LA VERSIÓN (TRACEABILITY)
           Identificación precisa de quién creó ESTA versión específica de los datos y cuándo.
           ---------------------------------------------------------------------------------------- */
        `DC`.`created_at`                  AS `Fecha_Creacion_Registro`,
        `DC`.`updated_at`                  AS `Fecha_Ultima_Edicion`,
        
        /* Resolución de Identidad: Convertimos el ID de usuario en Nombre Real (Formato Apellidos) */
        CONCAT(IFNULL(`IP_Crt`.`Apellido_Paterno`,''), ' ', IFNULL(`IP_Crt`.`Apellido_Materno`,''), ' ', IFNULL(`IP_Crt`.`Nombre`,'')) AS `Creado_Por_Nombre`,
        `U_Crt`.`Ficha`                    AS `Creado_Por_Ficha`

    FROM `Picade`.`DatosCapacitaciones` `DC` -- TABLA FÍSICA (Fuente de Verdad)
    
    /* JOIN 1: Vista Maestra (Optimización: Reutilizamos la lógica de presentación ya existente) */
    INNER JOIN `Picade`.`Vista_Capacitaciones` `VC` 
        ON `DC`.`Id_DatosCap` = `VC`.`Id_Detalle_de_Capacitacion`
    
    /* JOINS DE AUDITORÍA: Enlace reflexivo para obtener los datos del autor del cambio */
    LEFT JOIN `Picade`.`Usuarios` `U_Crt` 
        ON `DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `U_Crt`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `IP_Crt` 
        ON `U_Crt`.`Fk_Id_InfoPersonal` = `IP_Crt`.`Id_InfoPersonal`
    
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    /* ============================================================================================
       BLOQUE 3: GENERACIÓN DEL RESULTSET 2 (LISTA NOMINAL - BODY)
       Objetivo: Proveer la lista de asistencia detallada para la gestión de calificaciones.
       Fuente: `Vista_Gestion_de_Participantes` (Vista especializada en la relación N:M).
       ============================================================================================ */
    SELECT 
        `Id_Registro_Participante`    AS `Id_Inscripcion`, -- PK Relacional (Para Updates/Deletes)
        `Ficha_Participante`          AS `Ficha`,
        
        /* Formato Estándar Administrativo: "PATERNO MATERNO NOMBRE" */
        CONCAT(`Ap_Paterno_Participante`, ' ', `Ap_Materno_Participante`, ' ', `Nombre_Pila_Participante`) AS `Nombre_Alumno`,
        
        /* KPIs de Rendimiento Individual */
        `Porcentaje_Asistencia`       AS `Asistencia`,
        `Calificacion_Numerica`       AS `Calificacion`,
        
        /* Estado del Participante (Semántica de Negocio) */
        `Resultado_Final`             AS `Estatus_Alumno`,      -- Texto (ej: APROBADO)
        `Detalle_Resultado`           AS `Descripcion_Estatus`  -- Tooltip (ej: Calif >= 80)

    FROM `Picade`.`Vista_Gestion_de_Participantes`
    WHERE `Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion
    
    /* Regla de Ordenamiento: Alfabético estricto por Apellido Paterno */
    ORDER BY `Ap_Paterno_Participante` ASC, `Ap_Materno_Participante` ASC, `Nombre_Pila_Participante` ASC;

    /* ============================================================================================
       BLOQUE 4: GENERACIÓN DEL RESULTSET 3 (BITÁCORA HISTÓRICA - FOOTER)
       Objetivo: Construir la línea de tiempo completa de cambios del curso ("Time Travel Debugging").
       Lógica: Buscamos a todos los "Hermanos" (registros que comparten el mismo Id_Capacitacion Padre).
       ============================================================================================ */
    SELECT 
        /* Identificador de la versión histórica */
        `H_VC`.`Id_Detalle_de_Capacitacion` AS `Id_Version_Historica`,
        
        /* Timestamp del Cambio */
        `H_VC`.`Fecha_Creacion_Detalle`     AS `Fecha_Movimiento`,
        
        /* Autoría del Cambio (Responsabilidad) */
        CONCAT(IFNULL(`H_IP`.`Apellido_Paterno`,''), ' ', IFNULL(`H_IP`.`Nombre`,'')) AS `Responsable_Cambio`,
        
        /* LA JUSTIFICACIÓN (Core Audit Requirement): ¿Por qué se hizo este cambio? */
        `H_VC`.`Observaciones`              AS `Justificacion_Cambio`,
        
        /* Snapshot del Estado en ese momento (Fotografía Histórica) */
        `H_VC`.`Nombre_Completo_Instructor` AS `Instructor_Asignado`,
        `H_VC`.`Nombre_Sede`                AS `Sede_Asignada`,
        `H_VC`.`Estatus_Curso`              AS `Estatus_En_Ese_Momento`,
        `H_VC`.`Fecha_Inicio`               AS `Fecha_Inicio_Programada`,
        `H_VC`.`Fecha_Fin`                  AS `Fecha_Fin_Programada`,
        
        /* Bandera de Contexto UI: ¿Es esta la versión que estoy viendo arriba? */
        CASE 
            WHEN `H_VC`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion THEN 1 
            ELSE 0 
        END                                 AS `Es_Version_Visualizada`,
        
        /* Bandera de Vigencia Real: ¿Es esta la última versión activa del sistema? */
        `H_VC`.`Estatus_del_Registro`       AS `Es_Vigente`

    FROM `Picade`.`Vista_Capacitaciones` `H_VC` -- Usamos la vista para eficiencia en nombres
    
    /* Join manual para resolver el nombre del autor de CADA versión histórica */
    LEFT JOIN `Picade`.`DatosCapacitaciones` `H_DC` ON `H_VC`.`Id_Detalle_de_Capacitacion` = `H_DC`.`Id_DatosCap`
    LEFT JOIN `Picade`.`Usuarios` `H_U` ON `H_DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `H_U`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `H_IP` ON `H_U`.`Fk_Id_InfoPersonal` = `H_IP`.`Id_InfoPersonal`

    WHERE `H_VC`.`Id_Capacitacion` = v_Id_Padre_Capacitacion -- Filtro por PADRE para traer toda la familia
    
    /* Ordenamiento Cronológico Inverso: Lo más reciente primero (Top of Stack) */
    ORDER BY `H_VC`.`Id_Detalle_de_Capacitacion` DESC;

END$$

DELIMITER ;