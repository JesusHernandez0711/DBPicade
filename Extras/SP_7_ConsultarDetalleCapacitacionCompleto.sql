/* ====================================================================================================
   PROCEDIMIENTO: SP_ConsultarDetalleCapacitacionCompleto
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre: SP_ConsultarDetalleCapacitacionCompleto
   - Tipo: Consulta de Múltiples Conjuntos de Resultados (Multi-ResultSet Query)
   - Patrón de Diseño: "Master-Detail-History Aggregation" (Agregación Maestro-Detalle-Historia)
   - Nivel de Aislamiento: Read Committed
   - Complejidad Ciclomática: Media-Alta (Debido a la lógica de semáforos de estado)
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento constituye el **"Expediente Digital Maestro"** para la gestión de un curso.
   Su propósito es eliminar la fragmentación de la información, permitiendo al Coordinador Académico
   responder tres preguntas fundamentales en una sola interacción visual (Single Screen Experience):
   
     A) EL PRESENTE (Situational Awareness - ResultSet 1): 
        "¿En qué estado se encuentra el curso HOY?"
        Devuelve los datos operativos, logísticos y financieros. Incluye un "Semáforo de Edición"
        que dicta si el usuario puede modificar los datos o si está en modo "Solo Lectura".
     
     B) LOS ACTORES (Stakeholder Management - ResultSet 2): 
        "¿Quiénes son los alumnos inscritos y cuál es su rendimiento?"
        Provee la lista nominal oficial, ordenada administrativamente.
     
     C) EL PASADO (Forensic Audit Trail - ResultSet 3): 
        "¿Cómo ha evolucionado este curso desde su creación?"
        Construye una línea de tiempo completa (Timeline) de cambios, mostrando quién, cuándo y 
        por qué se modificó el curso, incluso si la versión actual es un "Archivado".

   3. ARQUITECTURA DE DATOS (MULTI-RESULTSET STRATEGY)
   ---------------------------------------------------
   Para optimizar el rendimiento de red (Network Latency) y reducir la carga transaccional en la BD,
   este SP empaqueta tres consultas lógicas independientes en un solo "Viaje de Ida y Vuelta".
   
   [RESULTSET 1: HEADER & CONTEXT] (Single Row)
      - Contenido: Datos inmutables (Identidad), Datos mutables (Logística) y Lógica de Bloqueo.
      - Lógica de Bloqueo (Kill Switch): Calcula la columna `Es_Solo_Lectura`. 
        Si el curso fue archivado (Padre=0) o es una versión histórica (Hijo=0), devuelve 1.
   
   [RESULTSET 2: BODY & PARTICIPANTS] (Multiple Rows)
      - Contenido: Nómina de alumnos.
   
   [RESULTSET 3: FOOTER & HISTORY LOG] (Multiple Rows)
      - Contenido: Bitácora cronológica inversa de todas las versiones del curso.
      - Fuente: Utiliza la `Vista_Capacitaciones` histórica para resolver nombres de instructores
        y sedes tal como eran en el momento del cambio.

   4. ESTRATEGIA DE INTEGRIDAD Y SEGURIDAD (DEFENSE IN DEPTH)
   ----------------------------------------------------------
   - [Validación Fail-Fast]: Rechazo inmediato de parámetros nulos.
   - [Descubrimiento Jerárquico]: El SP infiere el "Padre" (Folio) a partir de cualquier "Hijo",
     permitiendo navegar entre versiones sin perder el contexto global.
   - [Visibilidad Universal]: A diferencia de los listados operativos, este SP ignora las banderas
     de `Activo=0` para permitir la auditoría de cursos cancelados o archivados.

   ==================================================================================================== */

DELIMITER $$

-- Eliminamos la versión anterior para asegurar una compilación limpia.
-- DROP PROCEDURE IF EXISTS `SP_ConsultarDetalleCapacitacionCompleto`$$

CREATE PROCEDURE `SP_ConsultarDetalleCapacitacionCompleto`(
    /* -----------------------------------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------------------------------- */
    IN _Id_Detalle_Capacitacion INT -- [OBLIGATORIO] ID único de la versión específica (`DatosCapacitaciones`)
                                    -- que se desea inspeccionar. Puede ser la versión actual o una histórica.
)
BEGIN
    /* ============================================================================================
       BLOQUE 0: VARIABLES DE ENTORNO
       Definición de contenedores para la lógica de descubrimiento jerárquico.
       ============================================================================================ */
    DECLARE v_Id_Padre_Capacitacion INT; -- Almacenará el ID del Folio (Carpeta Madre) para agrupar el historial.

    /* ============================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA Y DESCUBRIMIENTO JERÁRQUICO (FAIL FAST)
       Objetivo: Asegurar la integridad de la petición antes de consumir recursos de lectura.
       ============================================================================================ */
    
    /* 1.1 Validación Defensiva de Tipos (Type Safety Check) */
    /* Evitamos ejecución de queries si el input es basura (nulo o negativo). */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador de la Capacitación es inválido.';
    END IF;

    /* 1.2 Descubrimiento del Padre (Parent Discovery Pattern) */
    /* Buscamos a qué "Carpeta" (Capacitacion) pertenece esta "Hoja" (DatosCapacitaciones). 
       NOTA CRÍTICA: Esta consulta se hace sobre la tabla física cruda para poder encontrar
       registros incluso si fueron dados de baja (Archivados). */
    SELECT `Fk_Id_Capacitacion` INTO v_Id_Padre_Capacitacion
    FROM `DatosCapacitaciones`
    WHERE `Id_DatosCap` = _Id_Detalle_Capacitacion
    LIMIT 1;

    /* 1.3 Verificación de Existencia (404 Not Found Handling) */
    /* Si la variable sigue siendo NULL después del SELECT, significa que el ID no existe en la base de datos.
       Lanzamos un error de negocio semántico para detener la ejecución. */
    IF v_Id_Padre_Capacitacion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La capacitación solicitada no existe o el ID es incorrecto.';
    END IF;

    /* ============================================================================================
       BLOQUE 2: GENERACIÓN DEL RESULTSET 1 (EL EXPEDIENTE MAESTRO - HEADER)
       Objetivo: Entregar el contexto operativo actual y el semáforo de permisos.
       ============================================================================================ */
    SELECT 
        /* ----------------------------------------------------------------------------------------
           GRUPO A: DATOS DE IDENTIDAD (INMUTABLES)
           Estos datos definen "QUÉ" es el curso. Son inherentes al Folio y no cambian entre versiones.
           ---------------------------------------------------------------------------------------- */
        `VC`.`Id_Capacitacion`,          -- ID del Contenedor Global
        `VC`.`Id_Detalle_de_Capacitacion`,        -- ID de la versión visualizada
        `VC`.`Numero_Capacitacion`         AS `Folio`,             -- Llave de Negocio (Business Key)
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,    -- Cliente Interno (Label)
        `VC`.`Nombre_Tema`                 AS `Tema`,        -- Contenido Académico (Label)
        `VC`.`Tipo_Instruccion`            AS `Tipo_Capacitacion`,        -- Clasificación Pedagógica (Label)
		`VC`.`Duracion_Horas`,                                            -- Carga horaria académica

        /* ----------------------------------------------------------------------------------------
           GRUPO B: DATOS DE CONFIGURACIÓN (MUTABLES - "ROBUST HYDRATION")
           Estos datos definen "CÓMO" se ejecuta el curso. Pueden cambiar en el tiempo.
           Se entregan en pares (ID + Texto) para garantizar la integridad del formulario de edición.
           ---------------------------------------------------------------------------------------- */
        
        -- [1] INSTRUCTOR: Responsable de la ejecución
        `DC`.`Fk_Id_Instructor`            AS `Id_Instructor_Selected`, -- [VALUE] Para v-model
        `VC`.`Nombre_Completo_Instructor`  AS `Instructor`,       -- [LABEL] Para fallback visual
        
        -- [2] SEDE: Ubicación física
        `DC`.`Fk_Id_CatCases_Sedes`        AS `Id_Sede_Selected`,       -- [VALUE]
        `VC`.`Nombre_Sede`                 AS `Sede`,             -- [LABEL]
        
        -- [3] MODALIDAD: Formato de entrega (Virtual/Presencial)
        `DC`.`Fk_Id_CatModalCap`           AS `Id_Modalidad_Selected`,  -- [VALUE]
        `VC`.`Nombre_Modalidad`            AS `Modalidad`,        -- [LABEL]
        
        /* ----------------------------------------------------------------------------------------
           GRUPO C: DATOS OPERATIVOS (ESCALARES)
           Valores planos que se pintan directamente en inputs de texto o datepickers.
           ---------------------------------------------------------------------------------------- */
        `DC`.`Fecha_Inicio`,
        `DC`.`Fecha_Fin`,
        
		`VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,   -- KPI Financiero (Integer)
        `VC`.`Asistentes_Reales`,

        -- [4] ESTATUS: Estado del flujo de trabajo (Programado/Finalizado)
        `DC`.`Fk_Id_CatEstCap`             AS `Id_Estatus_Selected`,    -- [VALUE]
        `VC`.`Estatus_Curso`               AS `Estatus_del_Curso`,          -- [LABEL]
        -- `VC`.`Codigo_Estatus`              AS `Codigo_Estatus_Global`,  -- [META] Para lógica de colores (Badge UI)
        
        `DC`.`Observaciones`               AS `Bitacora_Notas`,           -- Justificación de esta versión

        /* ----------------------------------------------------------------------------------------
           GRUPO D: SEMÁFORO DE CONTROL DE EDICIÓN (LÓGICA CRÍTICA DE NEGOCIO)
           Esta columna calculada es el cerebro de la UI. Le dice al Frontend si debe bloquear los inputs.
           
           REGLAS DE BLOQUEO:
           1. Si `Cap`.`Activo` = 0: El curso entero fue ARCHIVADO/CANCELADO. (Bloqueo Global).
           2. Si `DC`.`Activo` = 0: El usuario está viendo una versión antigua del historial. (Bloqueo Histórico).
           3. Solo si ambos son 1, se permite la edición.
           ---------------------------------------------------------------------------------------- */
        CASE 
            WHEN `Cap`.`Activo` = 0 THEN 1  -- ESTADO: ARCHIVADO (Solo Lectura)
            WHEN `DC`.`Activo` = 0 THEN 1   -- ESTADO: HISTÓRICO (Solo Lectura)
            ELSE 0                          -- ESTADO: VIGENTE (Editable)
        END                                AS `Es_Solo_Lectura`,

        /* ----------------------------------------------------------------------------------------
           GRUPO E: AUDITORÍA DE LA VERSIÓN
           Identificación precisa de quién creó ESTA versión específica de los datos.
           ---------------------------------------------------------------------------------------- */
        `DC`.`created_at`                  AS `Fecha_Creacion_Version`,
        `DC`.`updated_at`                  AS `Fecha_Ultima_Edicion`,
        /* Resolución de Identidad: ID -> Nombre Real */
        CONCAT(IFNULL(`IP`.`Nombre`,''), ' ', IFNULL(`IP`.`Apellido_Paterno`,'')) AS `Creado_Por_Nombre`

    FROM `Picade`.`DatosCapacitaciones` `DC` -- [FUENTE DE VERDAD]: Tabla Física
    
    /* JOIN 1: Vista Maestra (Optimización: Reutilizamos la lógica de presentación de textos) */
    INNER JOIN `Picade`.`Vista_Capacitaciones` `VC` 
        ON `DC`.`Id_DatosCap` = `VC`.`Id_Detalle_de_Capacitacion`
    
    /* JOIN 2: Padre Físico (Vital para leer el estatus de archivado global) */
    INNER JOIN `Picade`.`Capacitaciones` `Cap` 
        ON `DC`.`Fk_Id_Capacitacion` = `Cap`.`Id_Capacitacion`
    
    /* JOIN 3 & 4: Auditoría Reflexiva (Quién hizo el registro) */
    LEFT JOIN `Picade`.`Usuarios` `U` 
        ON `DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `U`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `IP` 
        ON `U`.`Fk_Id_InfoPersonal` = `IP`.`Id_InfoPersonal`
    
    /* FILTRO MAESTRO: Solo traemos la versión solicitada */
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
    
    /* [REGLA DE UX]: Ordenamiento Alfabético Estricto por Apellido Paterno (A-Z) */
    ORDER BY `Ap_Paterno_Participante` ASC, `Ap_Materno_Participante` ASC, `Nombre_Pila_Participante` ASC;

    /* ============================================================================================
       BLOQUE 4: GENERACIÓN DEL RESULTSET 3 (BITÁCORA HISTÓRICA DETALLADA - FOOTER)
       Objetivo: Construir la línea de tiempo completa de cambios del curso.
       Lógica: Buscamos a todos los "Hermanos" (registros que comparten el mismo Id_Capacitacion Padre).
       Uso: Permite al usuario ver la evolución: "Primero fue el Instructor A, luego se cambió al B".
       ============================================================================================ */
    SELECT 
        /* Identificador único de la versión histórica */
        `H_VC`.`Id_Detalle_de_Capacitacion` AS `Id_Version_Historica`,
        
        /* Timestamp del Cambio (Momento exacto de la bifurcación) */
        `H_VC`.`Fecha_Creacion_Detalle`     AS `Fecha_Movimiento`,
        
        /* Autoría del Cambio (Responsabilidad) */
        CONCAT(IFNULL(`H_IP`.`Apellido_Paterno`,''), ' ', IFNULL(`H_IP`.`Nombre`,'')) AS `Responsable_Cambio`,
        
        /* LA JUSTIFICACIÓN (Core Audit Requirement): ¿Por qué se hizo este cambio? */
        `H_VC`.`Observaciones`              AS `Justificacion_Cambio`,
        
        /* Snapshot Completo del Estado en ese momento (Fotografía Histórica) 
           Estos campos permiten comparar visualmente "Qué cambió" respecto a la versión actual. */
        `H_VC`.`Nombre_Completo_Instructor` AS `Instructor_En_Ese_Momento`,
        `H_VC`.`Nombre_Sede`                AS `Sede_En_Ese_Momento`,
        `H_VC`.`Estatus_Curso`              AS `Estatus_En_Ese_Momento`,
        `H_VC`.`Fecha_Inicio`               AS `Fecha_Inicio_Programada`,
        `H_VC`.`Fecha_Fin`                  AS `Fecha_Fin_Programada`,
        
        /* Bandera de Contexto UI: 
           ¿Es esta la versión que estoy viendo arriba en el Header? (Para resaltarla en la tabla) */
        CASE 
            WHEN `H_VC`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion THEN 1 
            ELSE 0 
        END                                 AS `Es_Version_Visualizada`,
        
        /* Bandera de Vigencia Real: 
           ¿Es esta la última versión activa del sistema? */
        `H_VC`.`Estatus_del_Registro`       AS `Es_Vigente`

    FROM `Picade`.`Vista_Capacitaciones` `H_VC` -- Usamos la vista histórica para eficiencia en nombres
    
    /* JOIN MANUAL PARA AUDITORÍA HISTÓRICA
       Necesitamos resolver el nombre del autor de CADA versión histórica individualmente. */
    LEFT JOIN `Picade`.`DatosCapacitaciones` `H_DC` 
        ON `H_VC`.`Id_Detalle_de_Capacitacion` = `H_DC`.`Id_DatosCap`
    LEFT JOIN `Picade`.`Usuarios` `H_U` 
        ON `H_DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `H_U`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `H_IP` 
        ON `H_U`.`Fk_Id_InfoPersonal` = `H_IP`.`Id_InfoPersonal`

    /* FILTRO DE AGRUPACIÓN FAMILIAR:
       Traemos todos los registros que compartan el mismo PADRE que la versión solicitada. */
    WHERE `H_VC`.`Id_Capacitacion` = v_Id_Padre_Capacitacion 
    
    /* Ordenamiento Cronológico Inverso: 
       Lo más reciente primero (Top of Stack). */
    ORDER BY `H_VC`.`Id_Detalle_de_Capacitacion` DESC;

END$$

DELIMITER ;

