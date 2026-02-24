/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_ConsultarCursosImpartidos
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (TECHNICAL DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial       : SP_ConsultarCursosImpartidos
   - Sistema:             : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Auditoria			  : Trazabilidad de Carga Docente e Historial de Instrucción
   - Clasificación        : Consulta de Historial Docente (Instructor Record Inquiry)
   - Patrón de Diseño     : Targeted Version Snapshot (Snapshot de Versión Específica)
   - Nivel de Aislamiento : READ COMMITTED
   - Dependencia Core     : Vista_Capacitaciones

   II. PROPÓSITO Y VALOR DE NEGOCIO (BUSINESS VALUE)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento es el pilar del Dashboard del Instructor. Permite al docente:
   1. GESTIÓN ACTUAL: Visualizar los cursos que tiene asignados y en ejecución.
   2. EVIDENCIA HISTÓRICA: Consultar cursos que ya impartió y fueron archivados.
   3. RESPONSABILIDAD: Garantizar que su nombre aparezca ligado únicamente a las versiones de curso 
      donde él fue el instructor titular, incluso si el curso tuvo múltiples reprogramaciones.

   III. LÓGICA DE FILTRADO INTELIGENTE (FORENSIC SNAPSHOT)
   ----------------------------------------------------------------------------------------------------------
   En un sistema transaccional dinámico, un curso puede cambiar de instructor entre versiones. 
   Para evitar que el historial de un instructor se "contamine" con datos de otros, el SP filtra por:
   
   - MAX(Id_DatosCap): Obtiene la versión más reciente de cada folio PERO condicionada a que 
     el instructor solicitado fuera el titular en esa versión específica.
   - SEMÁFORO DE VIGENCIA: Diferencia visualmente entre lo que es carga actual y lo que es historia.

   ========================================================================================================== */

DELIMITER $$

 DROP PROCEDURE IF EXISTS `SP_ConsultarCursosImpartidos`$$

CREATE PROCEDURE `SP_ConsultarCursosImpartidos`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IN _Id_Instructor INT -- ID único del usuario con rol de instructor/capacitador.
)
ProcCursosImpart: BEGIN
    
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN DE IDENTIDAD
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    IF _Id_Instructor IS NULL OR _Id_Instructor <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Instructor es obligatorio para recuperar el historial.' AS Mensaje,
               'VALIDACION_FALLIDA' AS Accion;
        LEAVE ProcCursosImpart;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: CONSULTA DE HISTORIAL DOCENTE (INSTRUCTION LOG ENGINE)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        -- [BLOQUE 1: IDENTIFICADORES Y FOLIOS]
        `VC`.`Id_Capacitacion`,               -- PK del curso padre.
        `VC`.`Id_Detalle_de_Capacitacion`,     -- PK de la versión específica (Id_DatosCap).
        
        -- GRUPO B: DATOS VISUALES
        `VC`.`Numero_Capacitacion`         AS `Folio`, -- Identificador institucional.
        
		`VC`.`Id_Subdireccion`,
        `VC`.`Clave_Subdireccion`,
        `VC`.`Nombre_Subdireccion`,
        
        `VC`.`Id_Gerencia`,
        `VC`.`Clave_Gerencia`  AS `Gerencia`,
        `VC`.`Nombre_Gerencia`,
        
		-- [BLOQUE 2: METADATA ACADÉMICA]
        `VC`.`Id_Tema`,
        `VC`.`Codigo_Tema`,
        `VC`.`Nombre_Tema`                 AS `Tema`, -- Contenido impartido.
        
        `VC`.`Tipo_Instruccion`,
        `VC`.`Duracion_Horas`              AS `Duracion`, -- Valor curricular para el instructor.
        
		-- El instructor es él mismo, pero enviamos los datos para consistencia del objeto
		`VC`.`Id_Instructor`,
        `VC`.`Ficha_Instructor`,
        `VC`.`Nombre_Instructor`			AS `Instructor`,
        
        -- [BLOQUE 3: LOGÍSTICA DE OPERACIÓN]
        `VC`.`Id_Sedes`,
        `VC`.`Codigo_Sede`,
        `VC`.`Nombre_Sede` AS `Sede`,          -- Ubicación del evento.
        
        `VC`.`Id_Modalidad`,
        `VC`.`Nombre_Modalidad` AS `Modalidad`, -- Método de entrega.
        
		-- GRUPO C: METADATOS TEMPORALES
        `VC`.`Fecha_Inicio`,	-- Apertura del curso.
        `VC`.`Fecha_Fin`,		-- Cierre del curso.
        YEAR(`VC`.`Fecha_Inicio`)          AS `Anio`,
        MONTHNAME(`VC`.`Fecha_Inicio`)     AS `Mes`,

        -- GRUPO D: ANALÍTICA (KPIs)
        -- [BLOQUE 4: MÉTRICAS DE IMPACTO]        
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        `VC`.`Asistentes_Manuales`         AS `No_Inscritos_en_Sistema`, 
        `VC`.`Participantes_Activos`       AS `Inscritos_en_Sistema`,   -- Total de alumnos vivos actualmente en lista.
        `VC`.`Total_Impacto_Real`          AS `Total_de_Asistentes_Reales`, -- Usamos la lógica del GREATEST calculada en la vista.
        `VC`.`Participantes_Baja`          AS `Total_de_Bajas`,
        `VC`.`Cupo_Disponible`,
        
        /* ------------------------------------------------------------------
           GRUPO E: ESTADO VISUAL
           Textos pre-calculados en la Vista para mostrar al usuario.
           ------------------------------------------------------------------ */
		/* -----------------------------------------------------------------------------------
           BLOQUE 6: CONTROL DE ESTADO Y CICLO DE VIDA
           El corazón del flujo de trabajo. Determina si el curso está vivo, muerto o finalizado.
           ----------------------------------------------------------------------------------- */
		`VC`.`Id_Estatus`, -- Mapeo numérico (4=Fin, 8=Canc, etc) Útil para lógica de colores en UI (ej: CANC = Rojo) CRÍTICO: ID necesario para el match() en Blade
        `VC`.`Codigo_Estatus_Capacitacion`,
        `VC`.`Estatus_Curso_Capacitacion`, -- (ej: "FINALIZADO", "CANCELADO") Estado operativo (En curso, Finalizado, etc).
        
        `VC`.`Observaciones`               AS `Bitacora_Notas`,

		/* En este se detalla por quien y cuando fue asignado como instructor Eso en el caso que la capacitación 
        Haya sido creada inicialmente con otro instructor Qué sepa cuándo fue asignado  y por quien
        */
        `DC`.`Fk_Id_Usuario_DatosCap_Created_by` AS `AsinadoPor`,
        
        -- [BLOQUE 5: TRAZABILIDAD DE ASIGNACIÓN (EL CORAZÓN DEL CAMBIO)]
        -- Aquí resolvemos quién asignó al instructor usando la Vista_Usuarios
        `U_Asignador`.`Ficha_Usuario`     AS `AsignadoPor_Ficha`,
        `U_Asignador`.`Nombre_Completo`   AS `AsignadoPor_Nombre`,
        
        -- [BLOQUE 6: AUDITORÍA]
        `DC`.`created_at`                  AS `Fecha_Asignacion`,

        -- GRUPO F: BANDERAS LÓGICAS Y AUDITORÍA
        -- este es para conocer si la capacitacion ya esta archivada, ya que si esta en 0 significa 
        -- que ya finalizo su ciclo de vida
        `Cap`.`Activo`                     AS `Estatus_Del_Registro`,
        
        /* BANDERA DE VISIBILIDAD (Soft Delete Check) 
           Permite al Frontend aplicar estilos (ej. opacidad) a registros archivados.
           SEMÁFORO DE VIGENCIA DOCENTE 
           Diferencia registros de operación activa de los de archivo histórico.
           Este se utilizará para calcular si el usuario es el instructor actual de esta capacitacion.
           Ya que sí el detalle de esta capacitación Está desactivado significa qué es ya no es el el instructor y fue replazado.
           Anteriormente manejábamos  un case En el que definíamos que si era 1 significaba que es él instructor actual 
           pero si era 0 significa que fue reemplazado esa logica la aplicaremos desde laravel nosotros le enviaremos los datos crudos.
           */
        -- `DC`.`Activo`                      AS `Es_Version_Vigente` -- Bandera específica de versión
		`VC`.`Estatus_del_Detalle`			AS `Es_Version_Vigente`
        
        /*
        Datos de la capacitación como saber en qué día fue creada la capacitación o 
        registrada en el sistema cuándo fue La Última Vez que la actualizaron 
        Y por quién  No estoy muy convencido demostrar esos datos por eso los silencie.
        `VC`.`CreadoElDia`,
        
        `VC`.`CreadoPor`,
        
        `VC`. `CreadoPor_Ficha`,
        
        `VC`.`CreadoPor_Nombre`,
        
        `VC`.`ActualzadoElDia`,
                
        `VC`.`ActualizadoPor`,
        
        `VC`.`ActualizadoPor_Ficha`,

		`VC`. `ActualizadoPor_Nombre`
        */
        
    FROM `PICADE`.`Vista_Capacitaciones` `VC`
    
    INNER JOIN `PICADE`.`Capacitaciones` `Cap` 
        ON `VC`.`Id_Capacitacion` = `Cap`.`Id_Capacitacion`
        
    -- Unión con la tabla física para filtrar por el instructor titular de la versión.
    INNER JOIN `PICADE`.`DatosCapacitaciones` `DC` 
        ON `VC`.`Id_Detalle_de_Capacitacion` = `DC`.`Id_DatosCap`
	
    -- JOIN 3: Con la Vista de Usuarios para humanizar al "Asignador"
    LEFT JOIN `PICADE`.`Vista_Usuarios` `U_Asignador`
        ON `DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `U_Asignador`.`Id_Usuario`
        
    WHERE `DC`.`Fk_Id_Instructor` = _Id_Instructor
    
    /* ------------------------------------------------------------------------------------------------------
       LÓGICA DE SNAPSHOT TITULAR (INSTRUCTOR-SPECIFIC MAX VERSION)
       Objetivo: Si un curso tuvo versiones con otros instructores, este subquery asegura que
       el instructor consultado solo vea la versión MÁS RECIENTE donde ÉL fue el responsable.
       ------------------------------------------------------------------------------------------------------ */
    AND `DC`.`Id_DatosCap` = (
        SELECT MAX(`DC2`.`Id_DatosCap`)
        FROM `PICADE`.`DatosCapacitaciones` `DC2`
        WHERE `DC2`.`Fk_Id_Capacitacion` = `VC`.`Id_Capacitacion`
          AND `DC2`.`Fk_Id_Instructor` = _Id_Instructor
    )
    
    -- Ordenamos para mostrar la carga docente actual y reciente primero.
    ORDER BY `DC`.`Activo` DESC, `VC`.`Fecha_Inicio` DESC;

END$$

DELIMITER ;