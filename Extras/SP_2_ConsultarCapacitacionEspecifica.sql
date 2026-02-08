/* ====================================================================================================
   PROCEDIMIENTO: SP_ConsultarCapacitacionEspecifica_
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Tipo de Artefacto:  Procedimiento Almacenado de Recuperación Compuesta (Composite Retrieval SP)
   - Patrón de Diseño:   "Master-Detail-History Aggregation" (Agregación Maestro-Detalle-Historia)
   - Nivel de Aislamiento: READ COMMITTED (Lectura Confirmada)
   
   2. VISIÓN DE NEGOCIO (BUSINESS VALUE PROPOSITION)
   -------------------------------------------------
   Este procedimiento actúa como el "Motor de Reconstrucción Forense" del sistema. 
   Su objetivo es materializar el estado exacto de una capacitación en un punto específico del tiempo ("Snapshot").
   
   Soluciona tres necesidades críticas del Coordinador Académico en una sola transacción:
     A) Consciencia Situacional (Header): ¿Qué es este curso y en qué estado se encuentra hoy?
     B) Gestión de Capital Humano (Body): ¿Quiénes asistieron exactamente a ESTA versión del curso?
     C) Auditoría de Trazabilidad (Footer): ¿Quién modificó el curso, cuándo y por qué razón?

   3. ESTRATEGIA DE AUDITORÍA (FORENSIC IDENTITY STRATEGY)
   -------------------------------------------------------
   Implementa una "Doble Verificación de Identidad" para distinguir responsabilidades:
     - Autor Intelectual (Origen): Se extrae de la tabla Padre (`Capacitaciones`). Revela quién creó el folio.
     - Autor Material (Versión): Se extrae de la tabla Hija (`DatosCapacitaciones`). Revela quién hizo el último cambio.

   4. INTERFAZ DE SALIDA (MULTI-RESULTSET CONTRACT)
   ------------------------------------------------
   El SP devuelve 3 tablas secuenciales (Rowsets) optimizadas para consumo por PDO/Laravel:
     [SET 1 - HEADER]: Metadatos del Curso + Banderas de Estado + Auditoría de Origen/Edición.
     [SET 2 - BODY]:   Lista Nominal de Participantes vinculados a esta versión.
     [SET 3 - FOOTER]: Historial de Versiones (Log cronológico inverso).
   ==================================================================================================== */
DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarCapacitacionEspecifica`$$

CREATE PROCEDURE `SP_ConsultarCapacitacionEspecifica`(
    /* ------------------------------------------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT CONTRACT)
       ------------------------------------------------------------------------------------------------
       [CRÍTICO]: Se recibe el ID del DETALLE (Hijo/Versión), NO del Padre. 
       Esto habilita la funcionalidad de "Máquina del Tiempo". Si el usuario selecciona una versión 
       antigua en el historial, este ID permite reconstruir el curso tal como era en el pasado.
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Detalle_Capacitacion INT -- Puntero primario (PK) a la tabla `DatosCapacitaciones`.
)
THIS_PROC: BEGIN

    /* ------------------------------------------------------------------------------------------------
       DECLARACIÓN DE VARIABLES DE ENTORNO (CONTEXT VARIABLES)
       Contenedores temporales para mantener la integridad referencial durante la ejecución.
       ------------------------------------------------------------------------------------------------ */
    DECLARE v_Id_Padre_Capacitacion INT; -- Almacena el ID de la Carpeta Maestra para agrupar el historial.

    /* ================================================================================================
       BLOQUE 1: DEFENSA EN PROFUNDIDAD Y VALIDACIÓN (FAIL FAST STRATEGY)
       Objetivo: Proteger el motor de base de datos rechazando peticiones incoherentes antes de procesar.
       ================================================================================================ */
    
    /* 1.1 Validación de Integridad de Tipos (Type Safety Check) */
    /* Evitamos la ejecución de planes de consulta costosos si el input es nulo o negativo. */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador de la capacitación es inválido.';
    END IF;

    /* 1.2 Descubrimiento Jerárquico (Parent Discovery Logic) */
    /* Buscamos a qué "Expediente" (Padre) pertenece esta "Hoja" (Versión). 
       Utilizamos una consulta optimizada por índice primario para obtener el `Fk_Id_Capacitacion`. */
    SELECT `Fk_Id_Capacitacion` INTO v_Id_Padre_Capacitacion
    FROM `DatosCapacitaciones`
    WHERE `Id_DatosCap` = _Id_Detalle_Capacitacion
    LIMIT 1;

    /* 1.3 Verificación de Existencia (404 Not Found Handling) */
    /* Si la variable sigue siendo NULL después del SELECT, significa que el registro no existe físicamente.
       Lanzamos un error semántico para informar al Frontend y detener la ejecución. */
    IF v_Id_Padre_Capacitacion IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La capacitación solicitada no existe en los registros.';
    END IF;

    /* ================================================================================================
       BLOQUE 2: RESULTSET 1 - CONTEXTO OPERATIVO Y AUDITORÍA (HEADER)
       Objetivo: Entregar los datos maestros del curso unificando Padre e Hijo.
       Complejidad: Media (Múltiples JOINs para resolución de identidades).
       ================================================================================================ */
       
    SELECT 
        /* -----------------------------------------------------------
           GRUPO A: IDENTIDAD DEL EXPEDIENTE (INMUTABLES - TABLA PADRE)
           Datos que definen la esencia del curso y no cambian con las ediciones.
           ----------------------------------------------------------- */
        `VC`.`Id_Capacitacion`,             -- ID Interno del Padre (Para referencias)
        `VC`.`Id_Detalle_de_Capacitacion`,  -- ID de la versión que estamos viendo (PK Actual)
        `VC`.`Numero_Capacitacion`         AS `Folio`,     -- Llave de Negocio (ej: CAP-2026-001)
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,  -- Dueño del Presupuesto (Cliente Interno)
        `VC`.`Nombre_Tema`                 AS `Tema`,      -- Materia Académica
        `VC`.`Tipo_Instruccion`            AS `Tipo_de_Capacitacion`, -- Clasificación (Teórico/Práctico)
        `VC`.`Duracion_Horas`              AS `Duracion`,  -- Metadata Académica

        /* -----------------------------------------------------------
           GRUPO B: CONFIGURACIÓN OPERATIVA (MUTABLES - TABLA HIJA)
           Datos logísticos que pueden cambiar en cada versión.
           Se entregan pares ID + TEXTO para "hidratar" los formularios de edición (v-model).
           ----------------------------------------------------------- */
        /* [Recurso Humano] */
        `DC`.`Fk_Id_Instructor`            AS `Id_Instructor_Selected`, -- ID para el Select
        `VC`.`Nombre_Completo_Instructor`  AS `Instructor`,             -- Texto para leer
        
        /* [Infraestructura] */
        `DC`.`Fk_Id_CatCases_Sedes`        AS `Id_Sede_Selected`,
        `VC`.`Nombre_Sede`                 AS `Sede`,
        
        /* [Metodología] */
        `DC`.`Fk_Id_CatModalCap`           AS `Id_Modalidad_Selected`,
        `VC`.`Nombre_Modalidad`            AS `Modalidad`,
        
        /* -----------------------------------------------------------
           GRUPO C: DATOS DE EJECUCIÓN (ESCALARES)
           Valores directos para visualización o edición.
           ----------------------------------------------------------- */
        `DC`.`Fecha_Inicio`,
        `DC`.`Fecha_Fin`,

        /* [KPIs de Cobertura] */
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        `VC`.`Asistentes_Reales`,
        
                /* [Ciclo de Vida] */
        `DC`.`Fk_Id_CatEstCap`             AS `Id_Estatus_Selected`,
        `VC`.`Estatus_Curso`               AS `Estatus_del_Curso`,
        -- `VC`.`Codigo_Estatus`              AS `Codigo_Estatus_Global`, -- Meta-dato para colorear badges en UI

        `DC`.`Observaciones`               AS `Bitacora_Notas`, -- Justificación técnica del cambio
        
        /* -----------------------------------------------------------
           GRUPO D: BANDERAS DE LÓGICA DE NEGOCIO (RAW STATE FLAGS)
           [IMPORTANTE]: El SP no decide si se puede editar. Entrega el estado crudo.
           Laravel usará esto: if (Registro=1 AND Detalle=1 AND Rol=Coord) -> AllowEdit.
           ----------------------------------------------------------- */
        `Cap`.`Activo`                     AS `Estatus_Del_Registro`,  -- 1 = Expediente Vivo / 0 = Archivado Globalmente
        `DC`.`Activo`                      AS `Estatus_Del_Detalle`,   -- 1 = Versión Vigente / 0 = Versión Histórica (Snapshot)

        /* -----------------------------------------------------------
           GRUPO E: AUDITORÍA FORENSE DIFERENCIADA (ORIGEN VS VERSIÓN ACTUAL)
           Aquí aplicamos la lógica de "Quién hizo qué" separando los momentos.
           ----------------------------------------------------------- */
        
        /* [MOMENTO 1: EL ORIGEN] - Datos provenientes de la Tabla PADRE (`Capacitaciones`) */
        /* ¿Cuándo nació el folio CAP-202X? */
        `Cap`.`created_at`                 AS `Fecha_Creacion_Original`,
        
        /* ¿Quién creó el folio? (Join Manual hacia el creador del Padre) */
        CONCAT(IFNULL(`IP_Creator`.`Nombre`,''), ' ', IFNULL(`IP_Creator`.`Apellido_Paterno`,'')) AS `Creado_Originalmente_Por`,

        /* [MOMENTO 2: LA VERSIÓN] - Datos provenientes de la Tabla HIJA (`DatosCapacitaciones`) */
        /* ¿Cuándo se guardó esta modificación específica? */
        `DC`.`created_at`                  AS `Fecha_Ultima_Modificacion`, 
        
        /* ¿Quién firmó esta modificación? (Join hacia el creador del Hijo) */
        CONCAT(IFNULL(`IP_Editor`.`Nombre`,''), ' ', IFNULL(`IP_Editor`.`Apellido_Paterno`,'')) AS `Ultima_Actualizacion_Por`

    /* ------------------------------------------------------------------------------------------------
       ORIGEN DE DATOS Y ESTRATEGIA DE VINCULACIÓN (JOIN STRATEGY)
       ------------------------------------------------------------------------------------------------ */
    FROM `Picade`.`DatosCapacitaciones` `DC` -- [FUENTE PRIMARIA]: El detalle específico solicitado
    
    /* JOIN 1: VISTA MAESTRA (Abstraction Layer) */
    /* Usamos la vista para obtener nombres pre-formateados y evitar repetir lógica de concatenación */
    INNER JOIN `Picade`.`Vista_Capacitaciones` `VC` 
        ON `DC`.`Id_DatosCap` = `VC`.`Id_Detalle_de_Capacitacion`
    
    /* JOIN 2: TABLA PADRE (Source of Truth) */
    /* Vital para obtener el Estatus Global y los datos de auditoría de creación original */
    INNER JOIN `Picade`.`Capacitaciones` `Cap`      
        ON `DC`.`Fk_Id_Capacitacion` = `Cap`.`Id_Capacitacion`
    
    /* JOIN 3: RESOLUCIÓN DE AUDITORÍA (EDITOR) */
    /* Conectamos la FK del HIJO (`DatosCapacitaciones`) con Usuarios -> InfoPersonal */
    LEFT JOIN `Picade`.`Usuarios` `U_Editor`        
        ON `DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `U_Editor`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `IP_Editor`  
        ON `U_Editor`.`Fk_Id_InfoPersonal` = `IP_Editor`.`Id_InfoPersonal`

    /* JOIN 4: RESOLUCIÓN DE AUDITORÍA (CREADOR) */
    /* Conectamos la FK del PADRE (`Capacitaciones`) con Usuarios -> InfoPersonal */
    LEFT JOIN `Picade`.`Usuarios` `U_Creator`       
        ON `Cap`.`Fk_Id_Usuario_Cap_Created_by` = `U_Creator`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `IP_Creator` 
        ON `U_Creator`.`Fk_Id_InfoPersonal` = `IP_Creator`.`Id_InfoPersonal`
    
    /* FILTRO MAESTRO */
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    /* ================================================================================================
       BLOQUE 3: RESULTSET 2 - NÓMINA DE PARTICIPANTES (BODY)
       Objetivo: Listar a las personas vinculadas estrictamente a ESTA versión del curso.
       Nota: Si estamos viendo una versión histórica, veremos a los alumnos tal como estaban en ese momento.
       Fuente: `Vista_Gestion_de_Participantes` (Vista optimizada para gestión escolar).
       ================================================================================================ */
    SELECT 
        `Id_Registro_Participante`    AS `Id_Inscripcion`,      -- PK para operaciones CRUD sobre el alumno
        `Ficha_Participante`          AS `Ficha`,
        /* Nombre formateado estilo lista de asistencia oficial (Paterno Materno Nombre) */
        CONCAT(`Ap_Paterno_Participante`, ' ', `Ap_Materno_Participante`, ' ', `Nombre_Pila_Participante`) AS `Nombre_Alumno`,
        `Porcentaje_Asistencia`       AS `Asistencia`,          -- 0-100%
        `Calificacion_Numerica`       AS `Calificacion`,        -- 0-10
        `Resultado_Final`             AS `Estatus_Alumno`,      -- Texto: Aprobado/Reprobado/Baja
        `Detalle_Resultado`           AS `Descripcion_Estatus`  -- Tooltip explicativo
    FROM `Picade`.`Vista_Gestion_de_Participantes`
    WHERE `Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion
    /* ORDENAMIENTO ESTRICTO: Alfabético por Apellido Paterno para facilitar el pase de lista */
    ORDER BY `Ap_Paterno_Participante` ASC, `Ap_Materno_Participante` ASC, `Nombre_Pila_Participante` ASC;

    /* ================================================================================================
       BLOQUE 4: RESULTSET 3 - LÍNEA DE TIEMPO HISTÓRICA (FOOTER)
       Objetivo: Reconstruir la historia completa del expediente (Padre) para navegación forense.
       Lógica: Busca a todos los "Hermanos" (registros que comparten el mismo Padre) y los ordena.
       ================================================================================================ */
    SELECT 
        /* Identificadores Técnicos para Navegación */
        `H_VC`.`Id_Detalle_de_Capacitacion` AS `Id_Version_Historica`, -- ID que se enviará al recargar este SP
        
        /* Momento exacto del cambio (Timestamp) */
        `H_VC`.`Fecha_Creacion_Detalle`     AS `Fecha_Movimiento`,
        
        /* Responsable del Cambio (Auditoría Histórica) */
        /* Obtenido mediante JOINs manuales en este bloque */
        CONCAT(IFNULL(`H_IP`.`Apellido_Paterno`,''), ' ', IFNULL(`H_IP`.`Nombre`,'')) AS `Responsable_Cambio`,
        
        /* Razón del Cambio (El "Por qué") */
        `H_VC`.`Observaciones`              AS `Justificacion_Cambio`,
        
        /* Snapshot de Datos Clave (Para previsualización rápida en la lista) */
        `H_VC`.`Nombre_Completo_Instructor` AS `Instructor_En_Ese_Momento`,
        `H_VC`.`Nombre_Sede`                AS `Sede_En_Ese_Momento`,
        `H_VC`.`Estatus_Curso`              AS `Estatus_En_Ese_Momento`,
        `H_VC`.`Fecha_Inicio`               AS `Fecha_Inicio_Programada`,
        `H_VC`.`Fecha_Fin`                  AS `Fecha_Fin_Programada`,
        
        /* --- UX MARKER (MARCADOR DE POSICIÓN) --- */
        /* Compara el ID de la fila histórica con el ID solicitado al inicio del SP.
           Si coinciden, devuelve 1. Esto permite al Frontend pintar la fila de color (ej: "Usted está aquí"). */
        CASE 
            WHEN `H_VC`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion THEN 1 
            ELSE 0 
        END                                 AS `Es_Version_Visualizada`,
        
        /* Bandera de Vigencia Real (Solo la última versión tendrá 1, el resto 0) */
        `H_VC`.`Estatus_del_Registro`       AS `Es_Vigente`

    FROM `Picade`.`Vista_Capacitaciones` `H_VC`
    
    /* JOIN MANUAL PARA AUDITORÍA HISTÓRICA */
    /* Necesario porque la Vista no expone los IDs de usuario creador por defecto.
       Vamos a las tablas físicas para recuperar quién creó cada versión antigua. */
    LEFT JOIN `Picade`.`DatosCapacitaciones` `H_DC` 
        ON `H_VC`.`Id_Detalle_de_Capacitacion` = `H_DC`.`Id_DatosCap`
    LEFT JOIN `Picade`.`Usuarios` `H_U`             
        ON `H_DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `H_U`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `H_IP`       
        ON `H_U`.`Fk_Id_InfoPersonal` = `H_IP`.`Id_InfoPersonal`
    
    /* FILTRO DE AGRUPACIÓN: Trae a todos los registros vinculados al mismo PADRE descubierto en el Bloque 1 */
    WHERE `H_VC`.`Id_Capacitacion` = v_Id_Padre_Capacitacion 
    
    /* ORDENAMIENTO: Cronológico Inverso (Lo más reciente arriba) para lectura natural */
    ORDER BY `H_VC`.`Id_Detalle_de_Capacitacion` DESC;

END$$

DELIMITER ;