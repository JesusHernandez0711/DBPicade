/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_ConsularMisCursos
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial       : SP_ConsularMisCursos
   - Sistema:             : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Clasificación        : Consulta de Historial Académico Personal (Student Record Inquiry)
   - Patrón de Diseño     : Latest Snapshot Filtering (Filtro de Última Versión)
   - Nivel de Aislamiento : READ COMMITTED
   - Dependencia Core     : Vista_Gestion_de_Participantes

   II. PROPÓSITO Y LÓGICA DE NEGOCIO (BUSINESS VALUE)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento alimenta el Dashboard del Participante. Su objetivo es mostrar el "Estado del Arte"
   de su capacitación. 
   
   [REGLA DE UNICIDAD]: 
   Si un curso (Folio) ha tenido varias versiones operativas (Reprogramaciones o Archivos), el sistema 
   debe mostrar solo la instancia más reciente donde el alumno estuvo inscrito. Esto previene la 
   confusión de ver "3 veces el mismo curso" en el historial.

   [REGLA DE VISIBILIDAD TOTAL]:
   A diferencia de los administradores que filtran por "Activo=1", el alumno debe ver sus cursos 
   FINALIZADOS y ARCHIVADOS, ya que forman parte de su currículum institucional y evidencia de formación.

   III. ARQUITECTURA DE FILTRADO (QUERY STRATEGY)
   ----------------------------------------------------------------------------------------------------------
   Se utiliza una subconsulta correlacionada con la función MAX(Id_Detalle_de_Capacitacion). 
   Esta estrategia garantiza que, de N registros para el mismo Folio y mismo Usuario, solo emerja 
   hacia el Frontend el registro con el ID más alto, que cronológicamente representa el último estado.

   ========================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsularMisCursos`$$

CREATE PROCEDURE `SP_ConsularMisCursos`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IN _Id_Usuario INT -- Identificador del participante autenticado en la sesión.
)
ProcMisCursos: BEGIN
    
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN DE ENTRADA
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IF _Id_Usuario IS NULL OR _Id_Usuario <= 0 
		THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario es obligatorio para la consulta.' AS Mensaje, 
               'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcMisCursos;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CONSULTA DE HISTORIAL UNIFICADO (THE TRUTH ENGINE)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
		-- [BLOQUE 1: IDENTIFICADORES DE NAVEGACIÓN]
		-- Identificadores de Navegación (Handles)

        `VGP`.`Id_Registro_Participante`,      -- PK de la relación Alumno-Curso.
        `VGP`.`Id_Capacitacion`,               -- [CORREGIDO]: ID de la tabla maestra (Padre).
        `VGP`.`Id_Detalle_de_Capacitacion`,    -- ID de la instancia operativa específica (Hijo).
        `VGP`.`Folio_Curso`,                   -- Referencia institucional (Numero_Capacitacion).

		-- [BLOQUE 2: METADATA DEL CONTENIDO]
        -- Metadatos del Contenido (Course Context)
        `VGP`.`Tema_Curso`,                    -- Título del tema impartido.
        `VGP`.`Fecha_Inicio`,                  -- Cronología de ejecución.
        `VGP`.`Fecha_Fin`,                     -- Cierre del curso.
        `VGP`.`Duracion_Horas`,                -- Carga horaria oficial.
        `VGP`.`Sede`,                          -- Ubicación física o lógica.
        `VGP`.`Modalidad`,                     -- Método de impartición.
        `VGP`.`Instructor_Asignado`,           -- Quién impartió la capacitación.
        `VGP`.`Estatus_Global_Curso`,          -- Estado de la capacitación (FINALIZADO, ARCHIVADO, etc.).
        
        -- [BLOQUE 3: DESEMPEÑO DEL PARTICIPANTE]
        -- Resultados Individuales (Performance Data)
        `VGP`.`Porcentaje_Asistencia`,         -- % de presencia física.
        `VGP`.`Calificacion_Numerica`,         -- Nota decimal asentada.
        `VGP`.`Resultado_Final` AS `Estatus_Participante`, -- APROBADO, REPROBADO, ASISTIÓ.
        `VGP`.`Detalle_Resultado`,             -- Regla de negocio aplicada.
        `VGP`.`Nota_Auditoria` AS `Justificacion`, -- Inyección forense de por qué hubo cambios.
        
        -- [BLOQUE 4: TRAZABILIDAD]
        -- Auditoría (Traceability)
        `VGP`.`Fecha_Inscripcion`,             -- Cuándo se unió el alumno.
        `VGP`.`Fecha_Ultima_Modificacion`      -- Última vez que se tocó el registro.

    FROM `Picade`.`Vista_Gestion_de_Participantes` `VGP`
    
    -- Filtro mandatorio por usuario solicitante
    WHERE `VGP`.`Ficha_Participante` = (SELECT `Ficha_Usuario` FROM `vista_usuarios` WHERE `Id_Usuario` = _Id_Usuario)
    
    /* ------------------------------------------------------------------------------------------------------
       LÓGICA SNAPSHOT (FILTRO ANTI-DUPLICADOS)
       Este AND asegura que si el Folio 'CAP-001' aparece 3 veces en la tabla por reprogramaciones,
       solo el ID de detalle más reciente sea seleccionado.
       ------------------------------------------------------------------------------------------------------ */
    AND `VGP`.`Id_Detalle_de_Capacitacion` = (
        SELECT MAX(`VSub`.`Id_Detalle_de_Capacitacion`)
        FROM `Picade`.`Vista_Gestion_de_Participantes` `VSub`
        WHERE `VSub`.`Folio_Curso` = `VGP`.`Folio_Curso`
          AND `VSub`.`Ficha_Participante` = `VGP`.`Ficha_Participante`
    )
    
    -- Ordenamiento cronológico inverso (Lo más nuevo al principio del Dashboard)
    ORDER BY `VGP`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;

