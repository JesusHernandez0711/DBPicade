USE Picade;

/* ====================================================================================================
   PROCEDIMIENTO: SP_ConsultarDetalleCapacitacionCompleto
   VERSIÓN: 3.1 (ROBUST HYDRATION & AUDIT READY)
   ====================================================================================================
   
   1. OBJETIVO TÉCNICO Y DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------------------
   Este procedimiento actúa como el "Expediente Digital Maestro" de un curso.
   Su función es recuperar el estado actual de una capacitación para dos fines críticos:
     
     A) VISUALIZACIÓN (DASHBOARD): 
        Mostrar al Coordinador la "Fotografía del Momento" con datos legibles (Nombres, Fechas formateadas).
     
     B) EDICIÓN (FORMULARIO REACTIVO): 
        Proveer los IDs crudos (Foreign Keys) necesarios para pre-cargar ("hidratar") los selectores 
        del formulario de edición, permitiendo modificar la logística del curso.

   2. ESTRATEGIA DE INTEGRIDAD PARA EDICIÓN (ROBUST HYDRATION PATTERN)
   ------------------------------------------------------------------
   Para garantizar que el formulario de edición funcione incluso en escenarios de borde (ej: recursos inactivos),
   este SP devuelve PARES DE DATOS (Value + Label) para cada campo editable:
   
      - [VALUE] (ej: `Id_Instructor_Selected`): Es el ID exacto guardado en la BD. El Frontend lo usa para 
        el binding del modelo (`v-model` / `ng-model`).
      
      - [LABEL] (ej: `Instructor_Texto`): Es el nombre asociado a ese ID. El Frontend lo usa como 
        "Fallback Visual". Si el instructor fue desactivado y ya no aparece en la lista de opciones, 
        el sistema muestra este texto en lugar de un error o un campo en blanco.

   3. PREPARACIÓN PARA BITÁCORA DE CAMBIOS (AUDIT READINESS)
   ---------------------------------------------------------
   Este SP consulta directamente la tabla `DatosCapacitaciones` (Detalle Operativo).
   En la arquitectura PICADE, los cambios (Instructor, Sede, Fechas) se registran creando una NUEVA fila
   en esta tabla, manteniendo el mismo `Id_Capacitacion` (Padre).
   
   Al consultar por `_Id_Detalle_Capacitacion`, estamos recuperando una "Versión Específica" de la historia.
   Esto permitirá en el futuro comparar:
      * Versión N (Actual): Instructor Juan.
      * Versión N-1 (Anterior): Instructor Pedro.
   
   4. ARQUITECTURA DE SALIDA (MULTI-RESULTSET CONTRACT)
   ----------------------------------------------------
   [RESULTSET 1: CONTEXTO, EDICIÓN Y AUDITORÍA] (Single Row)
      - Bloque A: Datos Inmutables (Identidad del Curso).
      - Bloque B: Datos Mutables (Logística Editable).
      - Bloque C: Auditoría Forense (Quién creó este registro y cuándo).
   
   [RESULTSET 2: LISTA NOMINAL] (Multiple Rows)
      - Nombres de alumnos (Formato Apellidos Primero).
      - Calificaciones y Asistencia.

   ==================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_ConsultarDetalleCapacitacionCompleto`$$

CREATE PROCEDURE `SP_ConsultarDetalleCapacitacionCompleto`(
    IN _Id_Detalle_Capacitacion INT -- [OBLIGATORIO] ID de la instancia operativa (`DatosCapacitaciones`)
)
BEGIN
    /* ============================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (DEFENSIVE PROGRAMMING)
       Objetivo: Evitar ejecuciones fallidas si el parámetro es basura.
       ============================================================================================ */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de la Capacitación es inválido.';
    END IF;

    /* ============================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA (FAIL FAST)
       Objetivo: Validar que el registro exista antes de intentar recuperar datos complejos.
       ============================================================================================ */
    IF NOT EXISTS (SELECT 1 FROM `DatosCapacitaciones` WHERE `Id_DatosCap` = _Id_Detalle_Capacitacion) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La capacitación solicitada no existe o fue eliminada.';
    END IF;

    /* ============================================================================================
       BLOQUE 3: GENERACIÓN DEL RESULTSET 1 (EL EXPEDIENTE MAESTRO)
       Objetivo: Entregar toda la información necesaria para pintar el Header y llenar el Formulario.
       ============================================================================================ */
    SELECT 
        /* ----------------------------------------------------------------------------------------
           GRUPO A: DATOS INMUTABLES (SOLO LECTURA)
           Estos datos definen la identidad del curso (Folio, Tema). NO se pueden editar en esta instancia
           porque romperían la integridad histórica.
           ---------------------------------------------------------------------------------------- */
        `VC`.`Id_Capacitacion`             AS `Id_Padre`,
        `VC`.`Numero_Capacitacion`         AS `Folio`,
        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia_Texto`, 
        `VC`.`Nombre_Tema`                 AS `Tema_Texto`,     
        `VC`.`Tipo_Instruccion`            AS `Tipo_Texto`,
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado`, 

        /* ----------------------------------------------------------------------------------------
           GRUPO B: DATOS MUTABLES (PAREJAS ID/TEXTO PARA FORMULARIOS ROBUSTOS)
           Estos son los campos que el Coordinador puede modificar. Se entregan PARES (Value, Label).
           - Value (`_Selected`): Para el binding lógico.
           - Label (`_Texto`): Para el feedback visual si el catálogo original cambió.
           ---------------------------------------------------------------------------------------- */
        `DC`.`Id_DatosCap`                 AS `Id_Detalle`, -- PK de la versión actual
        
        -- 1. INSTRUCTOR
        `DC`.`Fk_Id_Instructor`            AS `Id_Instructor_Selected`, -- ID (Value)
        `VC`.`Nombre_Completo_Instructor`  AS `Instructor_Texto`,       -- Nombre (Label)
        
        -- 2. SEDE
        `DC`.`Fk_Id_CatCases_Sedes`        AS `Id_Sede_Selected`,       
        `VC`.`Nombre_Sede`                 AS `Sede_Texto`,             
        
        -- 3. MODALIDAD
        `DC`.`Fk_Id_CatModalCap`           AS `Id_Modalidad_Selected`,  
        `VC`.`Nombre_Modalidad`            AS `Modalidad_Texto`,
        
        -- 4. ESTATUS
        `DC`.`Fk_Id_CatEstCap`             AS `Id_Estatus_Selected`,    
        `VC`.`Estatus_Curso`               AS `Estatus_Texto`,
        `VC`.`Codigo_Estatus`              AS `Codigo_Estatus_Global`, -- Útil para badges de color (Verde/Rojo)

        /* ----------------------------------------------------------------------------------------
           GRUPO C: DATOS OPERATIVOS DIRECTOS (INPUTS DE TEXTO/FECHA)
           Datos que se pintan directamente en inputs de texto o datepickers.
           ---------------------------------------------------------------------------------------- */
        `DC`.`Fecha_Inicio`,
        `DC`.`Fecha_Fin`,
        `DC`.`Observaciones`               AS `Bitacora_Notas`,
        `DC`.`AsistentesReales`            AS `Asistentes_Reales_Manual`,
        `VC`.`Duracion_Horas`,             

        /* ----------------------------------------------------------------------------------------
           GRUPO D: AUDITORÍA FORENSE (TRAZABILIDAD)
           Información vital para la Bitácora: ¿Quién creó ESTA versión específica de los datos?
           Nota: Esto puede ser diferente de quien creó el Folio original.
           ---------------------------------------------------------------------------------------- */
        `DC`.`created_at`                  AS `Fecha_Creacion_Registro`,
        `DC`.`updated_at`                  AS `Fecha_Ultima_Edicion`,
        
        /* Nombre del Responsable (Formato: Apellidos Primero) */
        CONCAT(IFNULL(`IP_Crt`.`Apellido_Paterno`,''), ' ', IFNULL(`IP_Crt`.`Apellido_Materno`,''), ' ', IFNULL(`IP_Crt`.`Nombre`,'')) AS `Creado_Por_Nombre`,
        `U_Crt`.`Ficha`                    AS `Creado_Por_Ficha`

    FROM `Picade`.`DatosCapacitaciones` `DC` -- TABLA FÍSICA (Fuente de Verdad)
    
    /* JOIN 1: Vista Maestra (Para enriquecer con textos sin reescribir lógica de concatenación) */
    INNER JOIN `Picade`.`Vista_Capacitaciones` `VC` 
        ON `DC`.`Id_DatosCap` = `VC`.`Id_Detalle_de_Capacitacion`
    
    /* JOINS DE AUDITORÍA: Resolvemos la identidad del usuario creador */
    LEFT JOIN `Picade`.`Usuarios` `U_Crt` 
        ON `DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `U_Crt`.`Id_Usuario`
    LEFT JOIN `Picade`.`Info_Personal` `IP_Crt` 
        ON `U_Crt`.`Fk_Id_InfoPersonal` = `IP_Crt`.`Id_InfoPersonal`

    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    /* ============================================================================================
       BLOQUE 4: RESULTSET 2 - LISTA NOMINAL (PARTICIPANTES)
       Objetivo: Entregar la lista de asistencia lista para renderizar.
       ============================================================================================ */
    SELECT 
        `Id_Registro_Participante`    AS `Id_Inscripcion`,
        `Ficha_Participante`          AS `Ficha`,
        
        /* Formato Oficial: Apellidos Nombre (Estándar Administrativo) */
        CONCAT(`Ap_Paterno_Participante`, ' ', `Ap_Materno_Participante`, ' ', `Nombre_Pila_Participante`) AS `Nombre_Alumno`,
        
        `Porcentaje_Asistencia`       AS `Asistencia`,
        `Calificacion_Numerica`       AS `Calificacion`,
        `Resultado_Final`             AS `Estatus_Alumno`,
        `Detalle_Resultado`           AS `Descripcion_Estatus`

    FROM `Picade`.`Vista_Gestion_de_Participantes`
    WHERE `Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion
    
    /* Ordenamiento Alfabético por Apellido Paterno (A-Z) */
    ORDER BY `Ap_Paterno_Participante` ASC, `Ap_Materno_Participante` ASC, `Nombre_Pila_Participante` ASC;

END$$

DELIMITER ;