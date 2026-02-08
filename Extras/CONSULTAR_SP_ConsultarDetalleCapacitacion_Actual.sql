/* ============================================================================================
   ARTEFACTO: PROCEDIMIENTO ALMACENADO [SP_ConsultarDetalleCapacitacion_Actual]
   ============================================================================================
   AUTOR: Arquitectura de Software PICADE
   VERSIÓN: 2.0 (SPLIT TABLE STRATEGY)

   1. OBJETIVO DE NEGOCIO
   ----------------------
   Recuperar la "FOTO ACTUAL" de una capacitación. Combina los datos inmutables (Título, Código)
   con la versión más reciente de los datos volátiles (Instructor, Fechas, Estatus).

   2. ESTRATEGIA TÉCNICA
   ---------------------
   - Se busca el registro en `DatosCapacitaciones` con el ID más alto (o fecha más reciente)
     para esa capacitación específica.
   - Se hace JOIN con `Usuarios` e `Info_Personal` para traer los nombres legibles.
   ============================================================================================ */

DELIMITER $$

CREATE PROCEDURE `SP_ConsultarDetalleCapacitacion_Actual`(
    IN _Id_Capacitacion INT
)
BEGIN
    SELECT 
        /* --- DATOS INMUTABLES (Tabla Padre) --- */
        `C`.`Id_Capacitacion`,
        `C`.`Codigo_Curso`,
        `C`.`Nombre_Curso`,
        -- Otros campos fijos...

        /* --- DATOS VOLÁTILES ACTUALES (Tabla Hija - Último Registro) --- */
        `DC`.`Fecha_Inicio`,
        `DC`.`Fecha_Fin`,
        `DC`.`Estatus`,
        
        /* --- INSTRUCTOR ACTUAL --- */
        `U_Inst`.`Ficha` AS `Ficha_Instructor`,
        CONCAT_WS(' ', `IP_Inst`.`Nombre`, `IP_Inst`.`Apellido_Paterno`, `IP_Inst`.`Apellido_Materno`) AS `Nombre_Instructor`,
        
        /* --- METADATOS DE LA VERSIÓN --- */
        `DC`.`Motivo_Cambio`, -- Por qué llegamos a esta versión
        `DC`.`created_at` AS `Fecha_Ultima_Actualizacion`

    FROM 
        `Capacitaciones` `C`
    
    /* JOIN para obtener SOLO el último registro de datos */
    INNER JOIN `DatosCapacitaciones` `DC`
        ON `C`.`Id_Capacitacion` = `DC`.`Fk_Id_Capacitacion`
    
    /* JOINs para resolver el nombre del Instructor */
    LEFT JOIN `Usuarios` `U_Inst` ON `DC`.`Fk_Id_Instructor` = `U_Inst`.`Id_Usuario`
    LEFT JOIN `Info_Personal` `IP_Inst` ON `U_Inst`.`Fk_Id_InfoPersonal` = `IP_Inst`.`Id_InfoPersonal`

    WHERE 
        `C`.`Id_Capacitacion` = _Id_Capacitacion
    ORDER BY 
        `DC`.`Id_DatosCapacitacion` DESC -- Importante: Ordenar para obtener el último
    LIMIT 1;

END$$

DELIMITER ;