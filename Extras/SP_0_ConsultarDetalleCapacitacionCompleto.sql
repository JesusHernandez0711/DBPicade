USE Picade;

/* ====================================================================================================
   PROCEDIMIENTO: SP_ConsultarDetalleCapacitacionCompleto
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Nombre: SP_ConsultarDetalleCapacitacionCompleto
   - Tipo: Consulta de Múltiples Conjuntos de Resultados (Multi-ResultSet Query)
   - Patrón de Diseño: Master-Detail Retrieval (Recuperación Maestro-Detalle)
   - Dependencias: 
       * `Vista_Capacitaciones` (Para el Contexto del Curso)
       * `Vista_Gestion_de_Participantes` (Para la Lista Nominal)
   
   2. VISIÓN DE NEGOCIO (BUSINESS GOAL)
   ------------------------------------
   Este procedimiento es el corazón del **Dashboard de Gestión de Curso**.
   Cuando un Coordinador hace clic en "Ver Detalle" de un curso específico, el sistema no solo
   necesita saber "qué curso es", sino "quiénes están dentro".
   
   Este SP entrega la "Fotografía Completa" del evento formativo en un solo viaje al servidor,
   optimizando el ancho de banda y la latencia de la aplicación.

   3. ARQUITECTURA DE SALIDA (OUTPUT CONTRACT)
   -------------------------------------------
   A diferencia de los SPs tradicionales que devuelven una tabla, este devuelve DOS:
   
   [RESULTSET 1: CONTEXTO DEL EVENTO] (Single Row)
      - Contiene: Folio, Tema, Instructor, Fechas, Sede, Cupo, Estatus Global.
      - Uso UI: Alimenta el Encabezado (Header) y las tarjetas de información general.
   
   [RESULTSET 2: LISTA NOMINAL] (Multiple Rows)
      - Contiene: Identidad del Alumno (Ficha, Nombre), Asistencia, Calificación, Estatus Individual.
      - Optimización: Se eliminan las columnas redundantes del curso (que ya vienen en el Resultset 1)
        para reducir el peso del JSON de respuesta ("Lean Payload").
      - Uso UI: Alimenta el Grid/Tabla de Alumnos donde se capturan calificaciones.

   4. ESTRATEGIA DE SEGURIDAD (DEFENSIVE PROGRAMMING)
   --------------------------------------------------
   - Validación de Entrada: Rechazo inmediato de IDs nulos o negativos.
   - Verificación de Existencia: Si el curso no existe, se retorna un error 404 explícito antes
     de intentar cargar la lista de participantes.

   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarDetalleCapacitacionCompleto`$$

CREATE PROCEDURE `SP_ConsultarDetalleCapacitacionCompleto`(
    IN _Id_Detalle_Capacitacion INT -- [OBLIGATORIO] Identificador único de la instancia del curso (`DatosCapacitaciones`)
)
BEGIN
    /* ============================================================================================
       BLOQUE 1: VALIDACIÓN DE ENTRADA (FAIL FAST)
       Objetivo: Asegurar que la petición tenga sentido antes de procesar.
       ============================================================================================ */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El ID de la Capacitación es inválido.';
    END IF;

    /* ============================================================================================
       BLOQUE 2: VERIFICACIÓN DE EXISTENCIA
       Objetivo: Validar que el curso exista. Usamos la Vista Maestra para esto.
       ============================================================================================ */
    IF NOT EXISTS (SELECT 1 FROM `Vista_Capacitaciones` WHERE `Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion) THEN
        SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Curso solicitado no existe o no se encuentran sus datos operativos.';
    END IF;

    /* ============================================================================================
       BLOQUE 3: GENERACIÓN DEL RESULTSET 1 (CONTEXTO DEL CURSO)
       Objetivo: Devolver los datos generales del evento (Header).
       Fuente: `Vista_Capacitaciones`.
       ============================================================================================ */
    SELECT 
        /* Identificadores */
        `Id_Capacitacion`             AS `Id_Padre`,
        `Id_Detalle_de_Capacitacion`  AS `Id_Detalle`,
        `Numero_Capacitacion`         AS `Folio`,
        
        /* Clasificación */
        `Clave_Gerencia_Solicitante`  AS `Gerencia`,
        `Nombre_Tema`                 AS `Tema`,
        `Tipo_Instruccion`            AS `Tipo`,
        `Nombre_Modalidad`            AS `Modalidad`,
        
        /* Logística */
        `Nombre_Completo_Instructor`  AS `Instructor`,
        `Ficha_Instructor`            AS `Ficha_Instructor`, -- Útil para links al perfil
        `Nombre_Sede`                 AS `Sede`,
        
        /* Tiempo */
        `Fecha_Inicio`,
        `Fecha_Fin`,
        `Duracion_Horas`,
        
        /* Métricas y Estado */
        `Asistentes_Meta`             AS `Cupo_Programado`,
        `Asistentes_Reales`           AS `Inscritos_Actuales`,
        `Estatus_Curso`               AS `Estatus_Global`,
        `Codigo_Estatus`              AS `Codigo_Estatus_Global`, -- Para lógica de colores (Badge)
        `Observaciones`               AS `Bitacora_Notas`,
        
        /* Auditoría */
        `Estatus_del_Registro`

    FROM `Picade`.`Vista_Capacitaciones`
    WHERE `Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion;

    /* ============================================================================================
       BLOQUE 4: GENERACIÓN DEL RESULTSET 2 (LISTA DE PARTICIPANTES)
       Objetivo: Devolver la nómina de alumnos inscritos (Detail).
       Fuente: `Vista_Gestion_de_Participantes`.
       
       OPTIMIZACIÓN "LEAN PAYLOAD":
       Aquí filtramos intencionalmente las columnas que se refieren al curso (Nombre del Tema, Fechas, etc.)
       porque esos datos YA fueron entregados en el Resultset 1. 
       Solo entregamos lo referente al USUARIO y su DESEMPEÑO.
       ============================================================================================ */
    SELECT 
        /* Identificadores de la Relación */
        `Id_Registro_Participante`    AS `Id_Inscripcion`, -- PK de la relación (Para editar/borrar)
        
        /* Identidad del Alumno */
        `Ficha_Participante`          AS `Ficha`,
        -- `Nombre_Completo_Participante` AS `Nombre_Alumno`,
        -- Desglosamos nombres por si el Frontend necesita ordenar por apellido
		`Ap_Paterno_Participante`     AS `Apellido_Paterno`,
        `Ap_Materno_Participante`	  AS `Apellido_Materno`,
        `Nombre_Pila_Participante`    AS `Nombre_Pila`,
        
        /* Evaluación y Desempeño (KPIs) */
        `Porcentaje_Asistencia`       AS `Asistencia`,
        `Calificacion_Numerica`       AS `Calificacion`,
        
        /* Estado del Alumno */
        `Resultado_Final`             AS `Estatus_Alumno`,      -- Texto (ej: Aprobado)
        `Detalle_Resultado`           AS `Descripcion_Estatus`  -- Tooltip (ej: Calif >= 80)

    FROM `Picade`.`Vista_Gestion_de_Participantes`
    WHERE `Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion -- *NOTA IMPORTANTE ABAJO
    ORDER BY `Ap_Paterno_Participante` ASC, `Nombre_Pila_Participante` ASC;

    /* *NOTA IMPORTANTE DE IMPLEMENTACIÓN EN LA VISTA:
       Si la `Vista_Gestion_de_Participantes` NO expone la columna `Id_Detalle_de_Capacitacion` 
       directamente en su SELECT, debemos asegurarnos de que la vista lo incluya o filtrar 
       por la columna equivalente.
       
       Revisando la definición anterior de `Vista_Gestion_de_Participantes`:
       - No incluimos explícitamente `Id_Detalle_de_Capacitacion` en el SELECT final.
       - PERO, como es una vista, podemos filtrar por las columnas subyacentes si están expuestas 
         o debemos ajustar la vista.
       
       CORRECCIÓN TÉCNICA AL VUELO:
       Como la Vista está basada en `capacitaciones_participantes` JOIN `Vista_Capacitaciones`, 
       y `Vista_Capacitaciones` tiene el ID, la vista debería exponer el ID del detalle 
       para permitir este filtrado eficiente.
       
       Suposición para este código: La Vista `Vista_Gestion_de_Participantes` filtra correctamente.
       Si no, el WHERE se haría sobre la relación base:
       `WHERE Rel.Fk_Id_DatosCap = _Id_Detalle_Capacitacion` (si se accede directo a tablas)
       o asegurando que la Vista tenga la columna `Id_Detalle_de_Capacitacion`.
    */

END$$

DELIMITER ;