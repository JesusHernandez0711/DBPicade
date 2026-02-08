/* ======================================================================================================
   PROCEDIMIENTO 4: SP_Obtener_Mis_Cursos
   ======================================================================================================
   
   PROPÓSITO:
   ----------
   Alimentar la sección "Mi Historial de Capacitación" en el Perfil del Usuario (Participante).
   Muestra ÚNICAMENTE la última versión (vigente) de cada capacitación para evitar duplicados.
   
   ARQUITECTURA:
   -------------
   Implementa el patrón "Latest Snapshot" para garantizar que cada capacitación aparezca
   solo UNA vez, mostrando la información más actualizada.
   
   ====================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Obtener_Mis_Cursos`$$

CREATE PROCEDURE `SP_Obtener_Mis_Cursos`(
    IN _Id_Usuario INT
)
ProcMisCursos: BEGIN
    
    /* VALIDACIÓN DE ENTRADA */
    IF _Id_Usuario IS NULL OR _Id_Usuario <= 0 THEN
        SELECT 'ERROR [400]: El ID del Usuario es obligatorio.' AS Mensaje;
        LEAVE ProcMisCursos;
    END IF;

    /* CONSULTA DE HISTORIAL
       Objetivo: Mostrar cursos Activos Y Archivados, pero solo una vez (la última versión).
    */
    SELECT 
        /* IDs para navegación */
        VGP.Id_Registro_Participante,
        VGP.Id_Detalle_de_Capacitacion,
        VGP.Folio_Curso,
        
        /* Información del Curso */
        VGP.Tema_Curso,
        VGP.Fecha_Inicio,
        VGP.Fecha_Fin,
        VGP.Duracion_Horas,
        VGP.Sede,
        VGP.Modalidad,
        VGP.Instructor_Asignado,
        VGP.Estatus_Global_Curso, -- Muestra "FINALIZADO", "ARCHIVADO", etc.
        
        /* Resultados del Usuario */
        VGP.Porcentaje_Asistencia,
        VGP.Calificacion_Numerica,
        VGP.Resultado_Final AS Estatus_Participante,
        VGP.Detalle_Resultado,
        VGP.Nota_Auditoria  AS Justificacion, -- Columna nueva
        
        /* Metadata */
        VGP.Fecha_Inscripcion,
        VGP.Fecha_Ultima_Modificacion

    FROM Picade.Vista_Gestion_de_Participantes VGP
    
    /* JOIN para filtrar por usuario */
    INNER JOIN Picade.capacitaciones_participantes CP 
        ON VGP.Id_Registro_Participante = CP.Id_CapPart
        
    WHERE CP.Fk_Id_Usuario = _Id_Usuario
    
    /* FILTRO INTELIGENTE (SNAPSHOT):
       En lugar de filtrar por 'Activo=1' (que oculta los archivados),
       filtramos para obtener SOLO la versión más reciente (ID más alto)
       que tenga este folio para este usuario.
       
       Esto elimina los duplicados históricos pero mantiene los cursos terminados/archivados.
    */
    AND VGP.Id_Detalle_de_Capacitacion = (
        SELECT MAX(VSub.Id_Detalle_de_Capacitacion)
        FROM Picade.Vista_Gestion_de_Participantes VSub
        INNER JOIN Picade.capacitaciones_participantes CPSub 
            ON VSub.Id_Registro_Participante = CPSub.Id_CapPart
        WHERE VSub.Folio_Curso = VGP.Folio_Curso -- Mismo Folio (Curso Padre)
          AND CPSub.Fk_Id_Usuario = _Id_Usuario -- Mismo Usuario
    )
    
    /* ORDENAMIENTO: Lo más reciente primero */
    ORDER BY VGP.Fecha_Inicio DESC;

END$$
DELIMITER ;