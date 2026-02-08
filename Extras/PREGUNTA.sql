ok ya entendi como funciona este PERO NECESITO SABER QUE PARA LA PROXIMA FASE COMO TE EXPLICO LAS CAPACITACIONES TENDRAN UNA BITACORA. EN LA CUAL SE REQUIERE LO SIGUIENTE SABER QUIEN FUE EL INSTRUCTOR ACTUAL Y EL ANTERIOR, SABER CUAL FUE EL OTRO CAMBIO QUE SE HIZO PORQUE, CUANDO Y PORQUIEN. ES DECIR SI HAY UN CAMBIO DE INSTRUCTOR, SEDE, MODALIDAD, O ESTATUS SE DEBE SABER PORQUE Y ASI COMPARAR.



USE Picade;



/* ====================================================================================================

   PROCEDIMIENTO: SP_ConsultarDetalleCapacitacionCompleto

   VERSIÓN: 3.0 (READY FOR EDITING & AUDIT)

   ====================================================================================================

   

   1. OBJETIVO DE NEGOCIO

   ----------------------

   Recuperar el expediente completo del curso para dos propósitos simultáneos:

     A) Visualización (Lectura humana: Nombres, Folios, Fechas formateadas).

     B) Edición (Lectura de sistema: IDs crudos para pre-cargar los Dropdowns).



   2. ESTRATEGIA DE "BINDING" PARA EDICIÓN

   ---------------------------------------

   Para que el formulario de "Editar Capacitación" funcione, el Frontend necesita saber qué opción

   marcar en los selectores. Por eso, este SP devuelve explícitamente las LLAVES FORÁNEAS (FKs)

   de los campos editables:

      - `Id_Instructor_Selected` -> Para el Dropdown de Instructores.

      - `Id_Sede_Selected`       -> Para el Dropdown de Sedes.

      - `Id_Modalidad_Selected`  -> Para el Dropdown de Modalidades.

      - `Id_Estatus_Selected`    -> Para el Dropdown de Estatus.



   3. ALCANCE DE LA EDICIÓN (INMUTABILIDAD DE CABECERA)

   ----------------------------------------------------

   Se distingue claramente entre datos INMUTABLES (Gerencia, Tema, Folio) que definen la identidad

   del curso, y datos MUTABLES (Instructor, Fechas) que definen la ejecución.

   Esto prepara el terreno para el sistema de "Versionado de Cambios".



   4. SALIDA (OUTPUT)

   ------------------

   [RESULTSET 1]: Contexto, Auditoría y IDs para Edición.

   [RESULTSET 2]: Lista de Participantes (Ordenada por Apellido).

   ==================================================================================================== */



DELIMITER $$



-- DROP PROCEDURE IF EXISTS `SP_ConsultarDetalleCapacitacionCompleto`$$



CREATE PROCEDURE `SP_ConsultarDetalleCapacitacionCompleto`(

    IN _Id_Detalle_Capacitacion INT -- [OBLIGATORIO] ID de la instancia operativa (`DatosCapacitaciones`)

)

BEGIN

    /* ============================================================================================

       BLOQUE 1: VALIDACIONES BÁSICAS

       ============================================================================================ */

    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN

        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID inválido.';

    END IF;



    IF NOT EXISTS (SELECT 1 FROM `DatosCapacitaciones` WHERE `Id_DatosCap` = _Id_Detalle_Capacitacion) THEN

        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La capacitación no existe.';

    END IF;



    /* ============================================================================================

       BLOQUE 2: RESULTSET 1 - EL EXPEDIENTE (CONTEXTO + IDS DE EDICIÓN)

       Objetivo: Traer la data visual (Vista) + la data cruda (Tabla Física) para los inputs.

       ============================================================================================ */

    SELECT 

        /* --- A. IDENTIFICADORES Y DATOS INMUTABLES (SOLO LECTURA EN EDICIÓN) --- */

        /* Estos campos NO se deben editar para no romper la integridad del folio */

        `VC`.`Id_Capacitacion`             AS `Id_Padre`,

        `VC`.`Numero_Capacitacion`         AS `Folio`,

        `VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia_Texto`, -- Solo visual

        `VC`.`Nombre_Tema`                 AS `Tema_Texto`,     -- Solo visual

        `VC`.`Tipo_Instruccion`            AS `Tipo_Texto`,

        `VC`.`Asistentes_Meta`             AS `Cupo_Programado`, -- Definido en cabecera



        /* --- B. DATOS MUTABLES (IDS PARA PRE-CARGAR DROPDOWNS DE EDICIÓN) --- */

        /* Aquí devolvemos los IDs exactos que están guardados en la tabla física `DatosCapacitaciones`.

           El Frontend usará estos valores en el `v-model` o `ng-model` de sus selectores. */

        

        `DC`.`Id_DatosCap`                 AS `Id_Detalle`,          -- PK de la fila a editar

        

        `DC`.`Fk_Id_Instructor`            AS `Id_Instructor_Selected`, -- Para Dropdown Instructores

        `VC`.`Nombre_Completo_Instructor`  AS `Instructor_Texto`,       -- Para Label visual

        

        `DC`.`Fk_Id_CatCases_Sedes`        AS `Id_Sede_Selected`,       -- Para Dropdown Sedes

        `VC`.`Nombre_Sede`                 AS `Sede_Texto`,             -- Para Label visual

        

        `DC`.`Fk_Id_CatModalCap`           AS `Id_Modalidad_Selected`,  -- Para Dropdown Modalidad

        `VC`.`Nombre_Modalidad`            AS `Modalidad_Texto`,

        

        `DC`.`Fk_Id_CatEstCap`             AS `Id_Estatus_Selected`,    -- Para Dropdown Estatus

        `VC`.`Estatus_Curso`               AS `Estatus_Texto`,

        `VC`.`Codigo_Estatus`              AS `Codigo_Estatus_Global`,  -- Para lógica de colores



        /* --- C. DATOS OPERATIVOS DIRECTOS (INPUTS DE TEXTO/FECHA) --- */

        `DC`.`Fecha_Inicio`,

        `DC`.`Fecha_Fin`,

        `DC`.`Observaciones`               AS `Bitacora_Notas`,

        `DC`.`AsistentesReales`            AS `Asistentes_Reales_Manual`, -- Dato capturado manualmente (si aplica)

        `VC`.`Duracion_Horas`,             -- Calculado o traído del tema



        /* --- D. AUDITORÍA FORENSE --- */

        `DC`.`created_at`                  AS `Fecha_Creacion_Registro`,

        `DC`.`updated_at`                  AS `Fecha_Ultima_Edicion`,

        

        /* Quién creó este registro específico */

        CONCAT(IFNULL(`IP_Crt`.`Apellido_Paterno`,''), ' ', IFNULL(`IP_Crt`.`Apellido_Materno`,''), ' ', IFNULL(`IP_Crt`.`Nombre`,'')) AS `Creado_Por_Nombre`,

        `U_Crt`.`Ficha`                    AS `Creado_Por_Ficha`



    FROM `Picade`.`DatosCapacitaciones` `DC` -- TABLA FÍSICA (Fuente de Verdad para Edición)

    

    /* JOIN 1: Vista Maestra (Para traer los textos bonitos y no re-hacer todos los joins) */

    INNER JOIN `Picade`.`Vista_Capacitaciones` `VC` 

        ON `DC`.`Id_DatosCap` = `VC`.`Id_Detalle_de_Capacitacion`

    

    /* JOINS DE AUDITORÍA (Para saber quién registró este movimiento) */

    LEFT JOIN `Picade`.`Usuarios` `U_Crt` 

        ON `DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `U_Crt`.`Id_Usuario`

    LEFT JOIN `Picade`.`Info_Personal` `IP_Crt` 

        ON `U_Crt`.`Fk_Id_InfoPersonal` = `IP_Crt`.`Id_InfoPersonal`



    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;



    /* ============================================================================================

       BLOQUE 3: RESULTSET 2 - LISTA NOMINAL (PARTICIPANTES)

       ============================================================================================ */

    SELECT 

        `Id_Registro_Participante`    AS `Id_Inscripcion`,

        `Ficha_Participante`          AS `Ficha`,

        

        /* Formato Oficial: Apellidos Nombre */

        CONCAT(`Ap_Paterno_Participante`, ' ', `Ap_Materno_Participante`, ' ', `Nombre_Pila_Participante`) AS `Nombre_Alumno`,

        

        `Porcentaje_Asistencia`       AS `Asistencia`,

        `Calificacion_Numerica`       AS `Calificacion`,

        `Resultado_Final`             AS `Estatus_Alumno`,

        `Detalle_Resultado`           AS `Descripcion_Estatus`



    FROM `Picade`.`Vista_Gestion_de_Participantes`

    WHERE `Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion

    ORDER BY `Ap_Paterno_Participante` ASC, `Ap_Materno_Participante` ASC, `Nombre_Pila_Participante` ASC;



END$$



DELIMITER ;