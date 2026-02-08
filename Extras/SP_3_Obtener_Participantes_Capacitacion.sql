/* ======================================================================================================
   PROCEDIMIENTO: SP_ConsularParticipantesCapacitacion
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Obtener la lista completa de participantes de una capacitación específica.
   Alimenta el grid de "Gestión de Participantes" en el módulo de Coordinador.
   
   INCLUYE:
   - Información completa del participante
   - Estatus actual (INSCRITO, ASISTIÓ, APROBADO, REPROBADO, BAJA)
   - Calificación y asistencia
   - Indicador visual de cupo
   
   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsularParticipantesCapacitacion`$$

CREATE PROCEDURE `SP_ConsularParticipantesCapacitacion`(
    IN _Id_Detalle_Capacitacion INT
)
ProcPartCapac: BEGIN

    /* -------------------------------------------------------------------------
       VALIDACIÓN
       ------------------------------------------------------------------------- */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: ID obligatorio.' AS Mensaje; 
        LEAVE ProcPartCapac;
    END IF;

    /* -------------------------------------------------------------------------
       RESULTSET 1: MÉTRICAS PARA LA CABECERA DEL GRID
       Esto sirve para refrescar los contadores: "18/20 inscritos".
       ------------------------------------------------------------------------- */
    SELECT 
        `VC`.`Numero_Capacitacion`     AS `Folio_Curso`,
        
        /* [KPIs de Cobertura] */
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        `VC`.`Asistentes_Manuales`, -- El campo que pueden editar
        
        /* [OPTIMIZACIÓN]: Dato directo de la vista */        
		/* [NUEVO] CAMPOS DIRECTOS DE LA VISTA */
        `VC`.`Participantes_Activos`       AS `Inscritos_en_Sistema`,   -- El dato automático
        `VC`.`Total_Impacto_Real`          AS `Total_de_Asistentes_Reales`,         -- El resultado final (GREATEST)
        `VC`.`Participantes_Baja` 		   AS `Total_de_Bajas`,
        `VC`.`Cupo_Disponible`
        
    FROM `Picade`.`Vista_Capacitaciones` `VC`
    WHERE `VC`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion;

    /* -------------------------------------------------------------------------
       RESULTSET 2: DATOS PARA EL GRID (TABLA)
       Lista pura de alumnos. Tu Frontend decide si pinta la fila roja o verde
       basándose en 'Estatus_Participante'.
       ------------------------------------------------------------------------- */
    SELECT 
        /* IDs para acciones (Editar/Borrar) */
        `VGP`.`Id_Registro_Participante`   AS `Id_Inscripcion`,
        
        /* Datos Visuales */
        `VGP`.`Ficha_Participante`         AS `Ficha`,
        CONCAT(`VGP`.`Ap_Paterno_Participante`, ' ', `VGP`.`Ap_Materno_Participante`, ' ', `VGP`.`Nombre_Pila_Participante`) AS `Nombre_Alumno`,
        
        /* Inputs Editables */
        `VGP`.`Porcentaje_Asistencia`      AS `Asistencia`,
        `VGP`.`Calificacion_Numerica`      AS `Calificacion`,
        
        /* Estado */
        `VGP`.`Resultado_Final`            AS `Estatus_Participante`, -- Texto: 'INSCRITO', 'BAJA', et`C`.
        `VGP`.`Detalle_Resultado`          AS `Descripcion_Estatus`,  -- Texto descriptivo
        `VGP`.`Nota_Auditoria`             AS `Justificacion`         -- Texto: Motivo de la baja/calificación

    FROM `Picade`.`Vista_Gestion_de_Participantes` `VGP`
    WHERE `VGP`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion
    
    /* Orden: Primero apellidos A-Z. (Opcional: Bajas al final) */
    ORDER BY `VGP`.`Ap_Paterno_Participante` ASC, `VGP`.`Ap_Materno_Participante` ASC;

END$$

DELIMITER ;
