/* ============================================================================================
   ARTEFACTO: PROCEDIMIENTO ALMACENADO [SP_ConsultarHistorialCambios_Capacitacion]
   ============================================================================================
   AUTOR: Arquitectura de Software PICADE
   VERSIÓN: 2.0 (SPLIT TABLE STRATEGY)

   1. OBJETIVO DE NEGOCIO
   ----------------------
   Mostrar la cronología completa de una capacitación. Permite responder:
   - "¿Quién fue el primer instructor asignado?"
   - "¿Cuándo cambiaron la fecha?"
   - "¿Por qué se canceló y luego se reactivó?"

   2. ESTRATEGIA DE VISUALIZACIÓN
   ------------------------------
   - Consulta la tabla `DatosCapacitaciones` filtrando por el ID del Padre.
   - Ordena descendente (Lo actual arriba, lo viejo abajo).
   - Resuelve nombres de Instructor y del Responsable del cambio (Admin/Coord).
   ============================================================================================ */

DELIMITER $$

CREATE PROCEDURE `SP_ConsultarHistorialCambios_Capacitacion`(
    IN _Id_Capacitacion INT
)
BEGIN
    SELECT 
        /* CUÁNDO OCURRIÓ */
        `DC`.`created_at` AS `Fecha_Movimiento`,
        
        /* QUÉ PASÓ (ESTADO EN ESE MOMENTO) */
        `DC`.`Estatus` AS `Estatus_En_Ese_Momento`,
        
        /* QUIÉN ERA EL INSTRUCTOR EN ESE MOMENTO */
        CONCAT_WS(' ', `IP_Inst`.`Nombre`, `IP_Inst`.`Apellido_Paterno`) AS `Instructor_Asignado`,
        `U_Inst`.`Ficha` AS `Ficha_Instructor`,

        /* POR QUÉ CAMBIÓ (JUSTIFICACIÓN) */
        `DC`.`Motivo_Cambio`,

        /* QUIÉN HIZO EL CAMBIO (AUDITORÍA) */
        CONCAT_WS(' ', `IP_Admin`.`Nombre`, `IP_Admin`.`Apellido_Paterno`) AS `Responsable_Cambio`

    FROM 
        `DatosCapacitaciones` `DC`

    /* Resolver Instructor de esa versión */
    LEFT JOIN `Usuarios` `U_Inst` ON `DC`.`Fk_Id_Instructor` = `U_Inst`.`Id_Usuario`
    LEFT JOIN `Info_Personal` `IP_Inst` ON `U_Inst`.`Fk_Id_InfoPersonal` = `IP_Inst`.`Id_InfoPersonal`

    /* Resolver Responsable del cambio (quien creó este registro de datos) */
    LEFT JOIN `Usuarios` `U_Admin` ON `DC`.`Fk_Usuario_Created_By` = `U_Admin`.`Id_Usuario`
    LEFT JOIN `Info_Personal` `IP_Admin` ON `U_Admin`.`Fk_Id_InfoPersonal` = `IP_Admin`.`Id_InfoPersonal`

    WHERE 
        `DC`.`Fk_Id_Capacitacion` = _Id_Capacitacion
    
    ORDER BY 
        `DC`.`Id_DatosCapacitacion` DESC;

END$$

DELIMITER ;