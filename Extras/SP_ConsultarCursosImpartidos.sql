/* ======================================================================================================
   PROCEDIMIENTO 5: SP_ConsultarCursosImpartidos
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Mostrar el historial de cursos que un instructor ha impartido.
   Útil para el perfil del instructor y para auditorías de carga docente.
   
   ARQUITECTURA:
   -------------
   Similar a SP_Obtener_Mis_Cursos pero filtrado por el campo Fk_Id_Instructor
   en lugar de la tabla de participantes.
   
   ====================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsultarCursosImpartidos`$$

CREATE PROCEDURE `SP_ConsultarCursosImpartidos`(
    IN _Id_Instructor INT
)
ProcCursosImpart: BEGIN
    
    /* VALIDACIÓN DE ENTRADA */
    IF _Id_Instructor IS NULL OR _Id_Instructor <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Instructor es obligatorio.' AS Mensaje;
        LEAVE ProcCursosImpart;
    END IF;

    /* CONSULTA MAESTRA DE INSTRUCTOR
       Objetivo: Mostrar historial de cursos impartidos (Activos y Archivados).
       Usa la 'Vista_Capacitaciones' para simplificar la lectura.
    */
    SELECT 
        /* IDs para navegación */
        `VC`.`Id_Capacitacion`,
        `VC`.Id_Detalle_de_Capacitacion,
        `VC`.Numero_Capacitacion          AS Folio_Curso,
        
        /* Información del Curso */
        `VC`.`Nombre_Tema`                  AS `Tema_Curso`,
        `VC`.`Duracion_Horas`,
        `VC`.`Clave_Gerencia_Solicitante`   AS `Gerencia_Solicitante`,
        
        /* Logística */
        `VC`.`Nombre_Sede`                  AS `Sede`,
        `VC`.`Nombre_Modalidad`             AS `Modalidad`,
        `VC`.`Fecha_Inicio`,
        `VC`.`Fecha_Fin`,
        
        /* Métricas */
        `VC`.`Asistentes_Meta`              AS `Cupo_Programado`,
        `VC`.`Asistentes_Reales`,
        
        /* [OPTIMIZACIÓN]: Ya no calculamos, solo leemos de la vista */
        `VC`.`Participantes_Activos`,

        /* Estatus "Congelado" */
        `VC`.`Estatus_Curso`                AS `Estatus_Snapshot`,
        
        /* [NUEVO] SEMÁFORO DE VIGENCIA 
           Esto resuelve tu duda. Le dice al usuario si este registro sigue vivo o si es historia.
        */
        CASE 
            WHEN `DC`.`Activo` = 1 
            THEN 'ACTUAL'      -- Sigue siendo el responsable
            ELSE 'HISTORIAL'                      -- Fue responsable, ya no (o ya acabó)
        END                             AS `Tipo_Registro`,

        /* [OPCIONAL] BANDERA BOOLEANA
           Para que el Frontend ponga el renglón en gris si es 0
        */
        `DC`.`Activo`                       AS `Es_Version_Vigente`,

        /* Metadata */
        `DC`.`created_at`                   AS `Fecha_Asignacion`
        
    FROM `Picade`.`Vista_Capacitaciones` `VC`
    
    /* FILTRO MAESTRO: Solo cursos donde este usuario es el instructor */
    /* Nota: Usamos la vista, pero el filtro debe ser sobre el ID real, 
       así que hacemos un join ligero con la tabla física para asegurar el ID */
    INNER JOIN `Picade`.`DatosCapacitaciones` `DC` 
        ON `VC`.`Id_Detalle_de_Capacitacion` = `DC`.`Id_DatosCap`
        
    WHERE `DC`.`Fk_Id_Instructor` = _Id_Instructor
    
    /* FILTRO SNAPSHOT INTELIGENTE:
       1. Si el curso sigue activo con este instructor -> Lo muestra.
       2. Si el curso se archivó (finalizó) con este instructor -> Lo muestra.
       3. Si el curso se reasignó a otro instructor en una versión posterior ->
          Muestra la versión histórica donde ESTE instructor dio la clase.
       
       Lógica: Mostramos la MAX(Version) PARA ESTE INSTRUCTOR ESPECÍFICO.
    */
    AND `DC`.`Id_DatosCap` = (
        SELECT MAX(`DC2`.`Id_DatosCap`)
        FROM `Picade`.`DatosCapacitaciones` `DC2`
        WHERE `DC2`.`Fk_Id_Capacitacion` = `VC`.`Id_Capacitacion`
          AND `DC2`.`Fk_Id_Instructor` = _Id_Instructor -- Clave: Max versión DE ÉL
    )
    
    /* ORDENAMIENTO: Cronológico inverso */
    ORDER BY `VC`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;