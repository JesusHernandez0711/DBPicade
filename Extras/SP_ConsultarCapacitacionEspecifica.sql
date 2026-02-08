DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_ConsultarCapacitacionEspecifica`$$

/* ====================================================================================================
   PROCEDIMEINTO: SP_ConsultarCapacitacionEspecifica
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Tipo de Artefacto:  Procedimiento Almacenado de Recuperación Compuesta (Composite Retrieval SP)
   - Patrón de Diseño:   "Master-Detail-History Aggregation" (Agregación Maestro-Detalle-Historia)
   - Complejidad:        O(1) - Acceso directo por Clave Primaria Indexada.
   - Nivel de Aislamiento: READ COMMITTED (Para evitar lecturas sucias durante la auditoría).

   2. VISIÓN DE NEGOCIO (BUSINESS VALUE)
   -------------------------------------
   Este procedimiento actúa como el "Motor de Reconstrucción Forense". Su objetivo es materializar
   el estado exacto de una capacitación en un punto específico del tiempo.
   A diferencia de una vista simple, este SP ensambla tres dimensiones de datos en una sola llamada 
   de red (Network Trip) para alimentar el Frontend (Laravel/Vue):
     A. La Realidad Operativa (Header): Datos logísticos, financieros y administrativos.
     B. El Capital Humano (Body): La lista nominal de participantes vinculados a esa versión.
     C. La Línea de Tiempo (Footer): El rastro de auditoría completo de cambios.

   3. ESTRATEGIA DE AUDITORÍA (FORENSIC STRATEGY)
   ----------------------------------------------
   Implementa una "Doble Verificación de Identidad":
     - Creador Intelectual (Origen): Quién registró el folio por primera vez en el sistema.
     - Editor Material (Versión): Quién realizó la modificación específica que se está visualizando.
   Esto permite distinguir responsabilidades en cursos de larga duración con múltiples administradores.

   4. INTERFAZ DE SALIDA (MULTI-RESULTSET CONTRACT)
   ------------------------------------------------
   El SP devuelve 3 tablas secuenciales (Rowsets) que deben ser consumidas por el driver PDO:
     [SET 1]: Metadatos del Curso y Banderas de Estado.
     [SET 2]: Lista de Asistencia (Snapshot de alumnos en ese momento).
     [SET 3]: Historial de Versiones (Log cronológico inverso).
   ==================================================================================================== */

CREATE PROCEDURE `SP_ConsultarCapacitacionEspecifica`(
    /* ------------------------------------------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ------------------------------------------------------------------------------------------------
       Se recibe el ID del DETALLE (Hijo), no del Padre. Esto es crucial para permitir la funcionalidad
       de "Máquina del Tiempo". Si recibiéramos el ID del Padre, solo podríamos mostrar lo actual.
       Al recibir el Hijo, podemos reconstruir cualquier versión pasada.
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Detalle_Capacitacion INT -- Puntero a la versión específica en `DatosCapacitaciones`.
)
BEGIN
    /* ------------------------------------------------------------------------------------------------
       DECLARACIÓN DE VARIABLES DE ENTORNO
       Contenedores para mantener el contexto relacional durante la ejecución.
       ------------------------------------------------------------------------------------------------ */
    DECLARE v_Id_Padre_Capacitacion INT; -- Almacena el ID de la Carpeta Maestra para agrupar el historial.

    /* ================================================================================================
       BLOQUE 1: DEFENSA EN PROFUNDIDAD Y VALIDACIÓN (FAIL FAST STRATEGY)
       Objetivo: Rechazar peticiones incoherentes antes de consumir recursos de lectura costosos.
       ================================================================================================ */
    
    /* 1.1 Validación de Integridad de Entrada */
    /* Evitamos inyecciones de nulos o números negativos que podrían causar Full Table Scans accidentales. */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador de la versión es inválido o nulo.';
    END IF;

    /* 1.2 Descubrimiento Jerárquico (Parent Discovery) */
    /* Buscamos a qué "Expediente" (Padre) pertenece esta "Hoja" (Versión). 
       Se usa una consulta ligera (Covering Index si es posible) para obtener el ID Padre. */
    SELECT `Fk_Id_Capacitacion` INTO v_Id_Padre_Capacitacion
    FROM `DatosCapacitaciones`
    WHERE `Id_DatosCap` = _Id_Detalle_Capacitacion
    LIMIT 1;

    /* 1.3 Verificación de Existencia (404 Handling) */
    /* Si la variable sigue nula, el registro no existe físicamente. Abortamos para no devolver basura. */
    IF v_Id_Padre_Capacitacion IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La versión de la capacitación solicitada no existe.';
    END IF;

    /* ================================================================================================
       BLOQUE 2: RESULTSET 1 - CONTEXTO OPERATIVO Y AUDITORÍA (HEADER)
       Objetivo: Entregar los datos maestros del curso.
       Arquitectura: JOINs estratégicos para resolver identidades (IDs -> Nombres) y calcular estados.
       ================================================================================================ */
    SELECT 
        /* -----------------------------------------------------------
           GRUPO A: IDENTIDAD DEL EXPEDIENTE (INMUTABLES)
           Datos que pertenecen al Padre y nunca cambian.
           ----------------------------------------------------------- */
        `VC`.`Id_Capacitacion`             AS `Id_Padre_Global`,    -- Referencia interna al expediente
        `VC`.`Id_Detalle_de_Capacitacion`  AS `Id_Version_Actual`,  -- Referencia a la versión visualizada
        `VC`.`Numero_Capacitacion`         AS `Folio`,              -- Llave de Negocio (Business Key)
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,           -- Centro de Costos
        `VC`.`Nombre_Tema`                 AS `Tema`,               -- Contenido Académico
        `VC`.`Tipo_Instruccion`            AS `Tipo_Capacitacion`,  -- Clasificación Pedagógica
        `VC`.`Duracion_Horas`              AS `Duracion`,           -- Metadata Académica

        /* -----------------------------------------------------------
           GRUPO B: CONFIGURACIÓN OPERATIVA (MUTABLES)
           Datos que pueden variar entre versiones. Se entregan pares
           ID + TEXTO para alimentar los formularios de edición (v-model).
           ----------------------------------------------------------- */
        /* Instructor */
        `DC`.`Fk_Id_Instructor`            AS `Id_Instructor_Selected`,
        `VC`.`Nombre_Completo_Instructor`  AS `Instructor`,
        
        /* Ubicación */
        `DC`.`Fk_Id_CatCases_Sedes`        AS `Id_Sede_Selected`,
        `VC`.`Nombre_Sede`                 AS `Sede`,
        
        /* Formato */
        `DC`.`Fk_Id_CatModalCap`           AS `Id_Modalidad_Selected`,
        `VC`.`Nombre_Modalidad`            AS `Modalidad`,
        
        /* Ciclo de Vida */
        `DC`.`Fk_Id_CatEstCap`             AS `Id_Estatus_Selected`,
        `VC`.`Estatus_Curso`               AS `Estatus_del_Curso`,
        `VC`.`Codigo_Estatus`              AS `Codigo_Estatus_Global`, -- Flag para renderizado de colores en UI

        /* -----------------------------------------------------------
           GRUPO C: DATOS DE EJECUCIÓN (ESCALARES)
           ----------------------------------------------------------- */
        `DC`.`Fecha_Inicio`,
        `DC`.`Fecha_Fin`,
        `DC`.`Observaciones`               AS `Bitacora_Notas`,     -- Justificación del cambio
        
        /* KPIs de Asistencia */
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        `VC`.`Asistentes_Reales`,

        /* -----------------------------------------------------------
           GRUPO D: BANDERAS DE LÓGICA DE NEGOCIO (RAW STATE FLAGS)
           Estas banderas permiten al Backend (Laravel) decidir los permisos
           de edición sin "hardcodear" lógica en SQL.
           ----------------------------------------------------------- */
        `Cap`.`Activo`                     AS `Estatus_Del_Registro`,  -- 1 = Expediente Vivo / 0 = Archivado Globalmente
        `DC`.`Activo`                      AS `Estatus_Del_Detalle`,   -- 1 = Versión Vigente / 0 = Versión Histórica

        /* -----------------------------------------------------------
           GRUPO E: AUDITORÍA FORENSE AVANZADA (DOBLE ORIGEN)
           Aquí resolvemos la pregunta: "¿Quién lo hizo?" en dos niveles.
           ----------------------------------------------------------- */
        
        /* NIVEL 1: EL ORIGEN (Génesis) */
        /* Fecha y Autor de la creación del Folio original (Tabla Padre) */
        `Cap`.`created_at`                 AS `Fecha_Creacion_Original`,
        CONCAT(IFNULL(`IP_Creator`.`Nombre`,''), ' ', IFNULL(`IP_Creator`.`Apellido_Paterno`,'')) AS `Creado_Originalmente_Por`,

        /* NIVEL 2: LA VERSIÓN (Snapshot) */
        /* Fecha y Autor de esta modificación específica (Tabla Hija) */
        `DC`.`created_at`                  AS `Fecha_Ultima_Modificacion`, 
        CONCAT(IFNULL(`IP_Editor`.`Nombre`,''), ' ', IFNULL(`IP_Editor`.`Apellido_Paterno`,'')) AS `Ultima_Actualizacion_Por`

    /* ------------------------------------------------------------------------------------------------
       ORIGEN DE DATOS Y RELACIONES (JOIN STRATEGY)
       ------------------------------------------------------------------------------------------------ */
    FROM `Picade`.`DatosCapacitaciones` `DC` -- [FUENTE PRIMARIA]: El detalle solicitado
    
    /* JOIN 1: VISTA MAESTRA (Para obtener textos pre-procesados y evitar lógica repetida) */
    INNER JOIN `Picade`.`Vista_Capacitaciones` `VC` 
        ON `DC`.`Id_DatosCap` = `VC`.`Id_Detalle_de_Capacitacion`
    
    /* JOIN 2: TABLA PADRE (Para obtener el Estatus Global y Auditoría de Origen) */
    INNER JOIN `Picade`.`Capacitaciones` `Cap`      
        ON `DC`.`Fk_Id_Capacitacion` = `Cap`.`Id_Capacitacion`
    
    /* JOIN 3 (COMPLEJO): RESOLUCIÓN DE AUDITORÍA DE EDICIÓN */
    /* Conectamos con el usuario que firmó el registro en la tabla HIJA (`DatosCapacitaciones`) */
    LEFT JOIN `Picade`.`Usuarios` `U_Editor`        
        ON `DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `U_Editor`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `IP_Editor`  
        ON `U_Editor`.`Fk_Id_InfoPersonal` = `IP_Editor`.`Id_InfoPersonal`

    /* JOIN 4 (COMPLEJO): RESOLUCIÓN DE AUDITORÍA DE ORIGEN */
    /* Conectamos con el usuario que firmó el registro en la tabla PADRE (`Capacitaciones`) */
    LEFT JOIN `Picade`.`Usuarios` `U_Creator`       
        ON `Cap`.`Fk_Id_Usuario_Cap_Created_by` = `U_Creator`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `IP_Creator` 
        ON `U_Creator`.`Fk_Id_InfoPersonal` = `IP_Creator`.`Id_InfoPersonal`
    
    /* FILTRO FINAL */
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    /* ================================================================================================
       BLOQUE 3: RESULTSET 2 - NÓMINA DE PARTICIPANTES (BODY)
       Objetivo: Listar a las personas vinculadas a ESTA versión específica del curso.
       Nota: Si esta es una versión histórica, mostrará a los alumnos tal como estaban en ese momento.
       ================================================================================================ */
    SELECT 
        `Id_Registro_Participante`    AS `Id_Inscripcion`,      -- PK para operaciones de baja individual
        `Ficha_Participante`          AS `Ficha`,
        /* Nombre formateado para listas oficiales */
        CONCAT(`Ap_Paterno_Participante`, ' ', `Ap_Materno_Participante`, ' ', `Nombre_Pila_Participante`) AS `Nombre_Alumno`,
        `Porcentaje_Asistencia`       AS `Asistencia`,
        `Calificacion_Numerica`       AS `Calificacion`,
        `Resultado_Final`             AS `Estatus_Alumno`,      -- Aprobado/Reprobado
        `Detalle_Resultado`           AS `Descripcion_Estatus`  -- Explicación técnica
    FROM `Picade`.`Vista_Gestion_de_Participantes`
    WHERE `Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion
    /* ORDENAMIENTO ESTRICTO: Alfabético por Apellido para coincidir con listas de papel */
    ORDER BY `Ap_Paterno_Participante` ASC, `Ap_Materno_Participante` ASC, `Nombre_Pila_Participante` ASC;

    /* ================================================================================================
       BLOQUE 4: RESULTSET 3 - LÍNEA DE TIEMPO HISTÓRICA (FOOTER)
       Objetivo: Reconstruir la historia completa del expediente (Padre) para navegación.
       UX Feature: Incluye una bandera `Es_Version_Visualizada` para resaltar la fila actual en la UI.
       ================================================================================================ */
    SELECT 
        /* Identificadores Técnicos */
        `H_VC`.`Id_Detalle_de_Capacitacion` AS `Id_Version_Historica`, -- ID para recargar el SP (Viaje en el tiempo)
        
        /* Momento del Cambio */
        `H_VC`.`Fecha_Creacion_Detalle`     AS `Fecha_Movimiento`,
        
        /* Responsable del Cambio (Auditoría Histórica) */
        CONCAT(IFNULL(`H_IP`.`Apellido_Paterno`,''), ' ', IFNULL(`H_IP`.`Nombre`,'')) AS `Responsable_Cambio`,
        
        /* Razón del Cambio */
        `H_VC`.`Observaciones`              AS `Justificacion_Cambio`,
        
        /* Snapshot de Datos Clave (Para previsualización en la lista) */
        `H_VC`.`Nombre_Completo_Instructor` AS `Instructor_En_Ese_Momento`,
        `H_VC`.`Nombre_Sede`                AS `Sede_En_Ese_Momento`,
        `H_VC`.`Estatus_Curso`              AS `Estatus_En_Ese_Momento`,
        `H_VC`.`Fecha_Inicio`               AS `Fecha_Inicio_Programada`,
        `H_VC`.`Fecha_Fin`                  AS `Fecha_Fin_Programada`,
        
        /* --- UX MARKER (MARCADOR DE POSICIÓN) --- */
        /* Compara el ID de la fila histórica con el ID solicitado al inicio del SP.
           Si coinciden, devuelve 1. Esto permite al Frontend pintar la fila de color (ej: "Estás Aquí"). */
        CASE 
            WHEN `H_VC`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion THEN 1 
            ELSE 0 
        END                                 AS `Es_Version_Visualizada`,
        
        /* Bandera de Vigencia Real (Solo una fila tendrá 1, el resto 0) */
        `H_VC`.`Estatus_del_Registro`       AS `Es_Vigente`

    FROM `Picade`.`Vista_Capacitaciones` `H_VC`
    
    /* JOIN MANUAL PARA AUDITORÍA HISTÓRICA
       Necesario porque la Vista no expone los IDs de usuario creador.
       Vamos a las tablas físicas para recuperar quién creó cada versión antigua. */
    LEFT JOIN `Picade`.`DatosCapacitaciones` `H_DC` ON `H_VC`.`Id_Detalle_de_Capacitacion` = `H_DC`.`Id_DatosCap`
    LEFT JOIN `Picade`.`Usuarios` `H_U`             ON `H_DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `H_U`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `H_IP`       ON `H_U`.`Fk_Id_InfoPersonal` = `H_IP`.`Id_InfoPersonal`
    
    /* FILTRO DE AGRUPACIÓN: Trae a todos los hermanos (Mismo Padre) */
    WHERE `H_VC`.`Id_Capacitacion` = v_Id_Padre_Capacitacion 
    
    /* ORDENAMIENTO: Cronológico Inverso (Lo más reciente arriba) */
    ORDER BY `H_VC`.`Id_Detalle_de_Capacitacion` DESC;

END$$

DELIMITER ;