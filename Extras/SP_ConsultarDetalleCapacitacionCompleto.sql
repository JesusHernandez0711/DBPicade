USE Picade;

/* ====================================================================================================
   PROCEDIMIENTO: SP_ConsultarDetalleCapacitacionCompleto
   VERSIÓN: 2.0 (AUDIT & TRACEABILITY ENHANCED)
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre: SP_ConsultarDetalleCapacitacionCompleto
   - Tipo: Consulta de Múltiples Conjuntos de Resultados (Multi-ResultSet Query)
   - Patrón: Master-Detail + Audit Enrichment
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Provee la "Hoja de Vida" completa del curso.
   Además de los datos operativos, esta versión incluye la **CAPA DE AUDITORÍA**:
   - Trazabilidad Temporal: ¿Cuándo se creó y cuándo se modificó por última vez?
   - Responsabilidad: ¿Qué usuario (Admin/Coordinador) dio de alta este registro?

   3. ARQUITECTURA DE SALIDA (OUTPUT CONTRACT)
   -------------------------------------------
   [RESULTSET 1: CONTEXTO Y AUDITORÍA] (Single Row)
      - Datos Operativos: Folio, Tema, Instructor, Fechas, Sede, Cupo, Estatus.
      - Datos de Auditoría: 
          * Fecha_Creacion (created_at)
          * Ultima_Edicion (updated_at)
          * Registrado_Por_Nombre (Nombre completo del usuario creador, formato Apellidos)
          * Registrado_Por_Ficha (Ficha del usuario creador)
   
   [RESULTSET 2: LISTA NOMINAL] (Multiple Rows)
      - Lista de alumnos con formato de nombre "Apellidos Nombre".

   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_ConsultarDetalleCapacitacionCompleto`$$

CREATE PROCEDURE `SP_ConsultarDetalleCapacitacionCompleto`(
    IN _Id_Detalle_Capacitacion INT -- [OBLIGATORIO] Identificador único de la instancia operativa
)
BEGIN
    /* ============================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (FAIL FAST)
       ============================================================================================ */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de la Capacitación es inválido.';
    END IF;

    /* ============================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA
       ============================================================================================ */
    IF NOT EXISTS (SELECT 1 FROM `Vista_Capacitaciones` WHERE `Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Curso solicitado no existe o no se encuentran sus datos operativos.';
    END IF;

    /* ============================================================================================
       BLOQUE 3: GENERACIÓN DEL RESULTSET 1 (CONTEXTO + AUDITORÍA)
       Objetivo: Devolver los datos del curso enriquecidos con la información de quién lo creó.
       ============================================================================================ */
    SELECT 
        /* --- GRUPO A: IDENTIFICADORES Y CLASIFICACIÓN --- */
        `VC`.`Id_Capacitacion`             AS `Id_Capacitacion`,
        `VC`.`Id_Detalle_de_Capacitacion`  AS `Id_Detalle`,
        `VC`.`Numero_Capacitacion`         AS `Folio`,
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,
        `VC`.`Nombre_Tema`                 AS `Tema`,
        `VC`.`Tipo_Instruccion`            AS `Tipo`,
        `VC`.`Nombre_Modalidad`            AS `Modalidad`,
        
        /* --- GRUPO B: LOGÍSTICA --- */
        `VC`.`Nombre_Completo_Instructor`  AS `Instructor`,
        `VC`.`Ficha_Instructor`            AS `Ficha_Instructor`,
        `VC`.`Nombre_Sede`                 AS `Sede`,
        `VC`.`Fecha_Inicio`,
        `VC`.`Fecha_Fin`,
        `VC`.`Duracion_Horas`,
        
        /* --- GRUPO C: MÉTRICAS Y ESTADO --- */
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado`,
        `VC`.`Asistentes_Reales`           AS `Inscritos_Actuales`,
        `VC`.`Estatus_Curso`               AS `Estatus_Global`,
        `VC`.`Codigo_Estatus`              AS `Codigo_Estatus_Global`,
        `VC`.`Observaciones`               AS `Bitacora_Notas`,
        `VC`.`Estatus_del_Registro`        AS `Activo`,

        /* --- GRUPO D: AUDITORÍA FORENSE (NUEVO) --- */
        /* Obtenemos las fechas directas de la tabla física */
        `Cap`.`created_at`                 AS `Fecha_Creacion`,
        `Cap`.`updated_at`                 AS `Ultima_Actualizacion`,
        
        /* Resolvemos la identidad del Creador (Admin/Coord) */
        -- `U_Crt`.`Ficha`                    AS `Registrado_Por_Ficha`,
        
        /* Formato Apellidos Primero para el Admin creador */
        CONCAT(
            IFNULL(`IP_Crt`.`Apellido_Paterno`, ''), ' ', 
            IFNULL(`IP_Crt`.`Apellido_Materno`, ''), ' ', 
            IFNULL(`IP_Crt`.`Nombre`, '')
        )                                AS `Registrado_Por_Nombre`

    FROM `Picade`.`Vista_Capacitaciones` `VC`
    
    /* JOIN 1: Acceso a la Tabla Física Padre para obtener IDs de Auditoría */
    INNER JOIN `Picade`.`Capacitaciones` `Cap`
        ON `VC`.`Id_Capacitacion` = `Cap`.`Id_Capacitacion`
    
    /* JOIN 2: Acceso al Usuario Creador */
    LEFT JOIN `Picade`.`Usuarios` `U_Crt` 
        ON `Cap`.`Fk_Id_Usuario_Cap_Created_by` = `U_Crt`.`Id_Usuario`
        
    /* JOIN 3: Acceso a los Datos Personales del Creador */
    LEFT JOIN `Picade`.`Info_Personal` `IP_Crt` 
        ON `U_Crt`.`Fk_Id_InfoPersonal` = `IP_Crt`.`Id_InfoPersonal`

    WHERE `VC`.`Id_Detalle_de_Capacitacion` = `_Id_Detalle_Capacitacion`;

    /* ============================================================================================
       BLOQUE 4: GENERACIÓN DEL RESULTSET 2 (LISTA DE PARTICIPANTES)
       ============================================================================================ */
    SELECT 
        /* Identificadores */
        `Id_Registro_Participante`    AS `Id_Inscripcion`,
        
        /* Identidad del Alumno */
        `Ficha_Participante`          AS `Ficha`,
        
        /* [REGLA]: Formato "Apellidos Nombre" */
        CONCAT(
            `Ap_Paterno_Participante`, ' ', 
            `Ap_Materno_Participante`, ' ', 
            `Nombre_Pila_Participante`
        )                             AS `Nombre_Alumno`,
        
        /* Desglose para edición */
        `Ap_Paterno_Participante`     AS `Apellido_Paterno`,
        `Ap_Materno_Participante`     AS `Apellido_Materno`,
        `Nombre_Pila_Participante`    AS `Nombre_Pila`,
        
        /* Evaluación */
        `Porcentaje_Asistencia`       AS `Asistencia`,
        `Calificacion_Numerica`       AS `Calificacion`,
        
        /* Estado y Auditoría del Participante */
        `Resultado_Final`             AS `Estatus_Alumno`,
        `Detalle_Resultado`           AS `Descripcion_Estatus`

    FROM `Picade`.`Vista_Gestion_de_Participantes`
    WHERE `Id_Detalle_de_Capacitacion` = `_Id_Detalle_Capacitacion`
    /* Ordenamiento administrativo estricto: A-Z por Apellido Paterno */
    ORDER BY `Ap_Paterno_Participante` ASC, `Ap_Materno_Participante` ASC, `Nombre_Pila_Participante` ASC;

END$$

DELIMITER ;