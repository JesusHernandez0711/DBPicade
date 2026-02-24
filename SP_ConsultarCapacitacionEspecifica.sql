
   /* ====================================================================================================
   PROCEDIMIENTO: SP_ConsultarCapacitacionEspecifica_
   ====================================================================================================
   
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   --------------------------------------
   - Tipo de Artefacto:  Procedimiento Almacenado de Recuperación Compuesta (Composite Retrieval SP)
   - Patrón de Diseño:   "Master-Detail-History Aggregation" (Agregación Maestro-Detalle-Historia)
   - Nivel de Aislamiento: READ COMMITTED (Lectura Confirmada)
   
   2. VISIÓN DE NEGOCIO (BUSINESS VALUE PROPOSITION)
   -------------------------------------------------
   Este procedimiento actúa como el "Motor de Reconstrucción Forense" del sistema. 
   Su objetivo es materializar el estado exacto de una capacitación en un punto específico del tiempo ("Snapshot").
   
   Soluciona tres necesidades críticas del Coordinador Académico en una sola transacción:
     A) Consciencia Situacional (Header): ¿Qué es este curso y en qué estado se encuentra hoy?
     B) Gestión de Capital Humano (Body): ¿Quiénes asistieron exactamente a ESTA versión del curso?
     C) Auditoría de Trazabilidad (Footer): ¿Quién modificó el curso, cuándo y por qué razón?

   3. ESTRATEGIA DE AUDITORÍA (FORENSIC IDENTITY STRATEGY)
   -------------------------------------------------------
   Implementa una "Doble Verificación de Identidad" para distinguir responsabilidades:
     - Autor Intelectual (Origen): Se extrae de la tabla Padre (`Capacitaciones`). Revela quién creó el folio.
     - Autor Material (Versión): Se extrae de la tabla Hija (`DatosCapacitaciones`). Revela quién hizo el último cambio.

   4. INTERFAZ DE SALIDA (MULTI-RESULTSET CONTRACT)
   ------------------------------------------------
   El SP devuelve 3 tablas secuenciales (Rowsets) optimizadas para consumo por PDO/Laravel:
     [SET 1 - HEADER]: Metadatos del Curso + Banderas de Estado + Auditoría de Origen/Edición.
     [SET 2 - BODY]:   Lista Nominal de Participantes vinculados a esta versión.
     [SET 3 - FOOTER]: Historial de Versiones (Log cronológico inverso).
   ==================================================================================================== */

DELIMITER $$

 DROP PROCEDURE IF EXISTS `SP_ConsultarCapacitacionEspecifica`$$

CREATE PROCEDURE `SP_ConsultarCapacitacionEspecifica`(
    /* ------------------------------------------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT CONTRACT)
       ------------------------------------------------------------------------------------------------
       [CRÍTICO]: Se recibe el ID del DETALLE (Hijo/Versión), NO del Padre. 
       Esto habilita la funcionalidad de "Máquina del Tiempo". Si el usuario selecciona una versión 
       antigua en el historial, este ID permite reconstruir el curso tal como era en el pasado.
       ------------------------------------------------------------------------------------------------ */
    IN _Id_Detalle_Capacitacion INT -- Puntero primario (PK) a la tabla `DatosCapacitaciones`.
)
THIS_PROC: BEGIN

    /* ------------------------------------------------------------------------------------------------
       DECLARACIÓN DE VARIABLES DE ENTORNO (CONTEXT VARIABLES)
       Contenedores temporales para mantener la integridad referencial durante la ejecución.
       ------------------------------------------------------------------------------------------------ */
    DECLARE v_Id_Padre_Capacitacion INT; -- Almacena el ID de la Carpeta Maestra para agrupar el historial.

    /* ================================================================================================
       BLOQUE 1: DEFENSA EN PROFUNDIDAD Y VALIDACIÓN (FAIL FAST STRATEGY)
       Objetivo: Proteger el motor de base de datos rechazando peticiones incoherentes antes de procesar.
       ================================================================================================ */
    
    /* 1.1 Validación de Integridad de Tipos (Type Safety Check) */
    /* Evitamos la ejecución de planes de consulta costosos si el input es nulo o negativo. */
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: El Identificador de la capacitación es inválido.';
    END IF;

    /* 1.2 Descubrimiento Jerárquico (Parent Discovery Logic) */
    /* Buscamos a qué "Expediente" (Padre) pertenece esta "Hoja" (Versión). 
       Utilizamos una consulta optimizada por índice primario para obtener el `Fk_Id_Capacitacion`. */
    SELECT `Fk_Id_Capacitacion` INTO v_Id_Padre_Capacitacion
    FROM `DatosCapacitaciones`
    WHERE `Id_DatosCap` = _Id_Detalle_Capacitacion
    LIMIT 1;

    /* 1.3 Verificación de Existencia (404 Not Found Handling) */
    /* Si la variable sigue siendo NULL después del SELECT, significa que el registro no existe físicamente.
       Lanzamos un error semántico para informar al Frontend y detener la ejecución. */
    IF v_Id_Padre_Capacitacion IS NULL THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: La capacitación solicitada no existe en los registros.';
    END IF;

    /* ================================================================================================
       BLOQUE 2: RESULTSET 1 - CONTEXTO OPERATIVO Y AUDITORÍA (HEADER)
       Objetivo: Entregar los datos maestros del curso unificando Padre e Hijo.
       Complejidad: Media (Múltiples JOINs para resolución de identidades).
       ================================================================================================ */
       
    SELECT 
        /* -----------------------------------------------------------
           GRUPO A: IDENTIDAD DEL EXPEDIENTE (INMUTABLES - TABLA PADRE)
           Datos que definen la esencia del curso y no cambian con las ediciones.
           ----------------------------------------------------------- */
        `VC`.`Id_Capacitacion`,             -- ID Interno del Padre (Para referencias)
        `VC`.`Id_Detalle_de_Capacitacion`,  -- ID de la versión que estamos viendo (PK Actual)
        
        `VC`.`Numero_Capacitacion`         AS `Folio`,     -- Llave de Negocio (ej: CAP-2026-001)
        
		`VC`.`Id_Subdireccion`,
		`VC`.`Clave_Subdireccion`,
		`VC`.`Nombre_Subdireccion`,
        
		`VC`.`Id_Gerencia`,
		`VC`.`Clave_Gerencia_Solicitante`  AS `Gerencia`,  -- Dueño del Presupuesto (Cliente Interno)
        `VC`.`Nombre_Gerencia`,
        
		`VC`.`Id_Tema`,
        `VC`.`Codigo_Tema`,
        `VC`.`Nombre_Tema`                 AS `Tema`,      -- Materia Académica
        `VC`.`Descripcion_Tema`,
        
		`VC`.`Tipo_Instruccion`,
        -- `VC`.`Tipo_Instruccion`            AS `Tipo_de_Capacitacion`, -- Clasificación (Teórico/Práctico)
        `VC`.`Duracion_Horas`              AS `Duracion`,  -- Metadata Académica

        /* -----------------------------------------------------------
           GRUPO B: CONFIGURACIÓN OPERATIVA (MUTABLES - TABLA HIJA)
           Datos logísticos que pueden cambiar en cada versión.
           Se entregan pares ID + TEXTO para "hidratar" los formularios de edición (v-model).
           ----------------------------------------------------------- */
        /* [Recurso Humano] */
		
        -- `DC`.`Fk_Id_Instructor`            AS `Id_Instructor`, -- ID para el Select
        -- `VC`.`Nombre_Completo_Instructor`  AS `Instructor`,             -- Texto para leer
        
        -- CONCAT(IFNULL(`VC`.`Nombre_Instructor`,''), ' ', IFNULL(`VC`.`Apellido_Paterno_Instructor`,''), ' ', IFNULL(`VC`.`Apellido_Materno_Instructor`,'')) AS `Instructor`,
        
        `VC`.`Id_Usuario`,
        `VC`.`Ficha_Instructor`,
         CONCAT(
			 IFNULL(`VC`.`Nombre_Instructor`,''), ' ',
			 IFNULL(`VC`.`Apellido_Materno_Instructor`,''), ' ',
			 IFNULL(`VC`.`Apellido_Paterno_Instructor`,'')
         ) AS `Instructor`,
        
        /* [Infraestructura] */
        -- `DC`.`Fk_Id_CatCases_Sedes`        AS `Id_Sede_Selected`,
        -- `VC`.`Nombre_Sede`                 AS `Sede`,
        
        `VC`.`Id_Sedes`,
        `VC`.`Codigo_Sede`,                  -- █ ¡AÑADE ESTA LÍNEA PARA QUE LARAVEL LO VEA! █
		`VC`.`Nombre_Sede`                 AS `Sede`,       -- Lugar de ejecución
        
        /* [Metodología] */
        -- `DC`.`Fk_Id_CatModalCap`           AS `Id_Modalidad_Selected`,
		
        `VC`.`Id_Modalidad`,
        `VC`.`Nombre_Modalidad`            AS `Modalidad`,
        
        /* -----------------------------------------------------------
           GRUPO C: DATOS DE EJECUCIÓN (ESCALARES)
           Valores directos para visualización o edición.
           ----------------------------------------------------------- */
   		`VC`.`Fecha_Inicio`,                                -- Día 1 del curso
	   	`VC`.`Fecha_Fin`,                                   -- Día N del curso
        
		YEAR(`VC`.`Fecha_Inicio`)          AS `Anio`,       -- Año Fiscal
		MONTHNAME(`VC`.`Fecha_Inicio`)     AS `Mes`, -- Etiqueta legible (Enero, Febrero...)


        /* ------------------------------------------------------------------
           GRUPO D: ANALÍTICA (KPIs)
           Métricas rápidas para visualización en el grid.
           ------------------------------------------------------------------*/
        /* -----------------------------------------------------------------------------------------
           [KPIs DE PLANEACIÓN - PLANIFICADO]
           Datos estáticos definidos al crear el curso. Representan la "Meta".
           ----------------------------------------------------------------------------------------- */

        -- Capacidad máxima teórica del aula o sala virtual.
         `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        
        -- Cantidad de asientos reservados manualmente por el coordinador (Override).
        -- Este valor tiene precedencia sobre el conteo automático en caso de ser mayor.
        -- Esta variable representa el total de personas que llevaron físicamente el curso pero que actualmente no tienen un registro en el sistema.
         `VC`.`Asistentes_Manuales`		  AS `No_Inscritos_en_Sistema`, 
        
		/* -----------------------------------------------------------------------------------------
           [KPIs DE OPERACIÓN - REALIDAD FÍSICA]
           Datos dinámicos calculados en tiempo real basados en la tabla de hechos.
           ----------------------------------------------------------------------------------------- */
        
        /* [CONTEO DE SISTEMA]: 
           Número exacto de filas en la tabla `Capacitaciones_Participantes` con estatus activo.
           Es la "verdad informática" de cuántos registros existen. */
         `VC`.`Participantes_Activos`       AS `Inscritos_en_Sistema`,   

        /* [IMPACTO REAL - REGLA HÍBRIDA]: 
           Este es el cálculo más importante del sistema. Aplica la función GREATEST().
           Fórmula: MAX(Inscritos_en_Sistema, Asistentes_Manuales).
           
           ¿Por qué?
           Si hay 5 inscritos en la BD, pero el Coordinador puso "20 Manuales" porque espera
           un grupo externo sin registro, el sistema debe considerar 20 asientos ocupados, no 5.
           Esto evita el "Overbooking" (Sobreventa) del aula. */
         `VC`.`Total_Impacto_Real`          AS `Total_de_Asistentes_Reales`, 

        /* [HISTÓRICO DE DESERCIÓN]:
           Conteo de participantes que estuvieron inscritos pero cambiaron a estatus "BAJA" (ID 5).
           Útil para medir la tasa de rotación o cancelación del curso. */
         `VC`.`Participantes_Baja`          AS `Total_de_Bajas`,

        /* [DISPONIBILIDAD FINAL]:
           El Delta matemático: (Meta - Impacto Real).
           Este valor es el que decide si se permiten nuevas inscripciones.
           Puede ser negativo si hubo sobrecupo autorizado. */
         `VC`.`Cupo_Disponible`,
        
		/* [Ciclo de Vida] */
        -- `DC`.`Fk_Id_CatEstCap`             AS `Id_Estatus_Selected`,
        -- `VC`.`Estatus_Curso`               AS `Estatus_del_Curso`,
        -- `VC`.`Codigo_Estatus`              AS `Codigo_Estatus_Global`, -- Meta-dato para colorear badges en UI
        
        /* ------------------------------------------------------------------
           GRUPO E: ESTADO VISUAL
           Textos pre-calculados en la Vista para mostrar al usuario.
           ------------------------------------------------------------------ */
		`VC`.`Id_Estatus_Capacitacion`	   AS `Id_Estatus`, -- Mapeo numérico (4=Fin, 8=Canc, etc)
        `VC`.`Estatus_Curso`               AS `Estatus_Texto`, -- (ej: "FINALIZADO", "CANCELADO")


		`VC`.`Observaciones`               AS `Bitacora_Notas`,           -- Justificación de esta versión
        
        /* -----------------------------------------------------------
           GRUPO D: BANDERAS DE LÓGICA DE NEGOCIO (RAW STATE FLAGS)
           [IMPORTANTE]: El SP no decide si se puede editar. Entrega el estado crudo.
           Laravel usará esto: if (Registro=1 AND Detalle=1 AND Rol=Coord) -> AllowEdit.
           ----------------------------------------------------------- */
        
		-- GRUPO F: BANDERAS LÓGICAS Y AUDITORÍA
        -- este es para conocer si la capacitacion ya esta archivada, ya que si esta en 0 significa 
        -- que ya finalizo su ciclo de vida
        `Cap`.`Activo`                     AS `Estatus_Del_Registro`,  -- 1 = Expediente Vivo / 0 = Archivado Globalmente
        
        /* BANDERA DE VISIBILIDAD (Soft Delete Check) 
           Permite al Frontend aplicar estilos (ej. opacidad) a registros archivados.
           SEMÁFORO DE VIGENCIA 
           Diferencia registros de operación activa de los de archivo histórico.
           Este se utilizará para calcular si el usuario es el esta viendo la version actual de esta capacitacion.
           Ya que sí el detalle de esta capacitación Está desactivado significa qué es ya no es la version del detalle acutal y fue replazada.
           Anteriormente manejábamos  un case En el que definíamos que si era 1 significaba que es él instructor actual 
           pero si era 0 significa que fue reemplazada esa logica la aplicaremos desde laravel nosotros le enviaremos los datos crudos.
           */
        `DC`.`Activo`                      AS `Estatus_Del_Detalle`,   -- 1 = Versión Vigente / 0 = Versión Histórica (Snapshot)

        /* ------------------------------------------------------------------
           GRUPO F: BANDERAS LÓGICAS (LOGIC FLAGS - CRITICAL)
           Aquí reside la inteligencia arquitectónica. Entregamos el estado físico puro.
           Laravel usará esto para: if (Estatus_Del_Registro == 1 && User->isAdmin()) { ... }
           
           GRUPO F: AUDITORÍA FORENSE DIFERENCIADA (ORIGEN VS VERSIÓN ACTUAL)
           Aquí aplicamos la lógica de "Quién hizo qué" separando los momentos.
           ------------------------------------------------------------------ */
           
		
		/* [MOMENTO 1: EL ORIGEN] - Datos provenientes de la Tabla PADRE (`Capacitaciones`) */
        /* ¿Cuándo nació el folio CAP-202X? */
         `VC`.`CreadoElDia`,
		
        /* ¿Quién creó el folio? (Join Manual hacia el creador del Padre) */
         `VC`.`CreadoPor`,
         
         CONCAT(
			IFNULL(`IP_Creator`.`Nombre`,''), ' ', 
            IFNULL(`IP_Creator`.`Apellido_Paterno`,'')
		) AS `Creado_Originalmente_Por`,
        
         `VC`.`ActualzadoElDia`,
                
         `VC`.`ActualizadoPor`,
         
        /* ¿Quién firmó esta modificación? (Join hacia el creador del Hijo) */
        CONCAT(IFNULL(`IP_Editor`.`Nombre`,''), ' ', IFNULL(`IP_Editor`.`Apellido_Paterno`,'')) AS `Ultima_Actualizacion_Por`

    /* ------------------------------------------------------------------------------------------------
       ORIGEN DE DATOS Y ESTRATEGIA DE VINCULACIÓN (JOIN STRATEGY)
       ------------------------------------------------------------------------------------------------ */
    FROM `PICADE`.`DatosCapacitaciones` `DC` -- [FUENTE PRIMARIA]: El detalle específico solicitado
    
    /* JOIN 1: VISTA MAESTRA (Abstraction Layer) */
    /* Usamos la vista para obtener nombres pre-formateados y evitar repetir lógica de concatenación */
    INNER JOIN `PICADE`.`Vista_Capacitaciones` `VC` 
        ON `DC`.`Id_DatosCap` = `VC`.`Id_Detalle_de_Capacitacion`
    
    /* JOIN 2: TABLA PADRE (Source of Truth) */
    /* Vital para obtener el Estatus Global y los datos de auditoría de creación original */
    INNER JOIN `PICADE`.`Capacitaciones` `Cap`      
        ON `DC`.`Fk_Id_Capacitacion` = `Cap`.`Id_Capacitacion`
    
    /* JOIN 3: RESOLUCIÓN DE AUDITORÍA (EDITOR) */
    /* Conectamos la FK del HIJO (`DatosCapacitaciones`) con Usuarios -> InfoPersonal */
    LEFT JOIN `PICADE`.`Usuarios` `U_Editor`        
        ON `DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `U_Editor`.`Id_Usuario`
    LEFT JOIN `PICADE`.`Info_Personal` `IP_Editor`  
        ON `U_Editor`.`Fk_Id_InfoPersonal` = `IP_Editor`.`Id_InfoPersonal`

    /* JOIN 4: RESOLUCIÓN DE AUDITORÍA (CREADOR) */
    /* Conectamos la FK del PADRE (`Capacitaciones`) con Usuarios -> InfoPersonal */
    LEFT JOIN `PICADE`.`Usuarios` `U_Creator`       
        ON `Cap`.`Fk_Id_Usuario_Cap_Created_by` = `U_Creator`.`Id_Usuario`
    LEFT JOIN `PICADE`.`Info_Personal` `IP_Creator` 
        ON `U_Creator`.`Fk_Id_InfoPersonal` = `IP_Creator`.`Id_InfoPersonal`
    
    /* FILTRO MAESTRO */
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    /* ================================================================================================
       BLOQUE 3: RESULTSET 2 - NÓMINA DE PARTICIPANTES (BODY)
       Objetivo: Listar a las personas vinculadas estrictamente a ESTA versión del curso.
       Nota: Si estamos viendo una versión histórica, veremos a los alumnos tal como estaban en ese momento.
       Fuente: `Vista_Gestion_de_Participantes` (Vista optimizada para gestión escolar).
       ================================================================================================ */
    
    SELECT
    
        /* -----------------------------------------------------------------------------------------
           [IDENTIFICADORES DE ACCIÓN - CRUD HANDLES]
           Datos técnicos ocultos necesarios para las operaciones de actualización.
           ----------------------------------------------------------------------------------------- */
        
        -- Llave Primaria (PK) de la relación Alumno-Curso.
        -- Este ID se envía al `SP_EditarParticipanteCapacitacion` o `SP_CambiarEstatus...`.
        `Id_Registro_Participante`    AS `Id_Inscripcion`,      -- PK para operaciones CRUD sobre el alumno

        /* -----------------------------------------------------------------------------------------
           [INFORMACIÓN VISUAL DEL PARTICIPANTE]
           Datos para que el humano identifique al alumno.
           ----------------------------------------------------------------------------------------- */
        
        -- ID Corporativo o Número de Empleado. Vital para diferenciar homónimos.
        `Ficha_Participante`          AS `Ficha`,

        -- Nombre Completo Normalizado.
        -- Se concatenan Paterno + Materno + Nombre para alinearse con los estándares
        -- de listas de asistencia impresas (orden alfabético por apellido).
        /* Nombre formateado estilo lista de asistencia oficial (Paterno Materno Nombre) */
        CONCAT(
            IFNULL(`Nombre_Pila_Participante`,''), ' ',
            IFNULL(`Ap_Materno_Participante`,''), ' ', 
            IFNULL(`Ap_Paterno_Participante`,'')
		) AS `Nombre_Alumno`,

        /* -----------------------------------------------------------------------------------------
           [INPUTS ACADÉMICOS EDITABLES]
           Datos que el coordinador puede modificar directamente en el grid.
           ----------------------------------------------------------------------------------------- */
        
        -- Porcentaje de Asistencia (0.00 - 100.00).
        -- Alimenta la barra de progreso visual en el Frontend.
        `Porcentaje_Asistencia`       AS `Asistencia`,          -- 0-100%

        -- Calificación Final Asentada (0.00 - 100.00).
        -- Si es NULL, el Frontend debe mostrar un input vacío o "Sin Evaluar".
        `Calificacion_Numerica`       AS `Calificacion`,        -- 0-10

        -- [AUDITORÍA FORENSE INYECTADA]:
        -- Contiene la cadena histórica de cambios (Timestamp + Motivo).
        -- Permite al coordinador saber por qué un alumno tiene una calificación extraña
        -- o por qué fue reactivado después de una baja.
        /* [NUEVO] Agregamos la justificación para verla en la tabla */
        `Nota_Auditoria`              AS `Justificacion`,

        /* -----------------------------------------------------------------------------------------
           [ESTADO DEL CICLO DE VIDA Y AUDITORÍA]
           Datos de control de flujo y trazabilidad.
           ----------------------------------------------------------------------------------------- */
        
        -- Estatus Semántico (Texto).
        -- Valores posibles: 'INSCRITO', 'ASISTIÓ', 'APROBADO', 'REPROBADO', 'BAJA'.
        -- Se usa para determinar el color de la fila (ej: Baja = Rojo, Aprobado = Verde).
        
        `Id_Estatus_Participante`,
        `Resultado_Final`             AS `Estatus_Alumno`,      -- Texto: Aprobado/Reprobado/Baja

        -- Descripción Técnica.
        -- Explica la regla de negocio aplicada (ej: "Reprobado por inasistencia > 20%").
        -- Se usa típicamente en un Tooltip al pasar el mouse sobre el estatus.
        `Detalle_Resultado`           AS `Descripcion_Estatus`,  -- Tooltip explicativo
        
		`Fecha_Inscripcion`,
        `Inscrito_Por`,
        `Fecha_Ultima_Modificacion`,
        `Modificado_Por`

    FROM `PICADE`.`Vista_Gestion_de_Participantes`
	
    -- Filtro estricto por la instancia del curso.
    WHERE `Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion

    /* -----------------------------------------------------------------------------------------
       [ESTRATEGIA DE ORDENAMIENTO - UX STANDARD]
       Ordenamos alfabéticamente por Apellido Paterno -> Materno -> Nombre.
       Esto es mandatorio para facilitar el cotejo visual contra listas físicas o de Excel.
       ----------------------------------------------------------------------------------------- */
    /* ORDENAMIENTO ESTRICTO: Alfabético por Apellido Paterno para facilitar el pase de lista */
    ORDER BY `Ap_Paterno_Participante` ASC, `Ap_Materno_Participante` ASC, `Nombre_Pila_Participante` ASC;

    /* ================================================================================================
       BLOQUE 4: RESULTSET 3 - LÍNEA DE TIEMPO HISTÓRICA (FOOTER)
       Objetivo: Reconstruir la historia completa del expediente (Padre) para navegación forense.
       Lógica: Busca a todos los "Hermanos" (registros que comparten el mismo Padre) y los ordena.
       ================================================================================================ */
    SELECT 
        /* Identificadores Técnicos para Navegación */
        `H_VC`.`Id_Detalle_de_Capacitacion` AS `Id_Version_Historica`, -- ID que se enviará al recargar este SP
        
        /* Momento exacto del cambio (Timestamp) */
        -- `H_VC`.`Fecha_Creacion_Detalle`     AS `Fecha_Movimiento`,
        `H_DC`.`created_at`                 AS `Fecha_Movimiento`,

        
        /* Responsable del Cambio (Auditoría Histórica) */
        /* Obtenido mediante JOINs manuales en este bloque */
        CONCAT(IFNULL(`H_IP`.`Apellido_Paterno`,''), ' ', IFNULL(`H_IP`.`Nombre`,'')) AS `Responsable_Cambio`,
        
        /* Razón del Cambio (El "Por qué") */
        `H_VC`.`Observaciones`              AS `Justificacion_Cambio`,
        
        /* Snapshot de Datos Clave (Para previsualización rápida en la lista) */
        -- `H_VC`.`Nombre_Completo_Instructor` AS `Instructor_En_Ese_Momento`,
        
        CONCAT(
			IFNULL(`H_VC`.`Nombre_Instructor`,''), ' ',
            IFNULL(`H_VC`.`Apellido_Paterno_Instructor`,''), ' ', 
            IFNULL(`H_VC`.`Apellido_Materno_Instructor`,'')
		) AS `Instructor_En_Ese_Momento`,
        
        `H_VC`.`Nombre_Sede`                AS `Sede_En_Ese_Momento`,
        `H_VC`.`Estatus_Curso`              AS `Estatus_En_Ese_Momento`,
        `H_VC`.`Fecha_Inicio`               AS `Fecha_Inicio_Programada`,
        `H_VC`.`Fecha_Fin`                  AS `Fecha_Fin_Programada`,
        
        /* --- UX MARKER (MARCADOR DE POSICIÓN) --- */
        /* Compara el ID de la fila histórica con el ID solicitado al inicio del SP.
           Si coinciden, devuelve 1. Esto permite al Frontend pintar la fila de color (ej: "Usted está aquí"). */
        CASE 
            WHEN `H_VC`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion THEN 1 
            ELSE 0 
        END                                 AS `Es_Version_Visualizada`,
        
        /* Bandera de Vigencia Real (Solo la última versión tendrá 1, el resto 0) */
        `H_VC`.`Estatus_del_Registro`       AS `Es_Vigente`

    FROM `PICADE`.`Vista_Capacitaciones` `H_VC`
    
    /* JOIN MANUAL PARA AUDITORÍA HISTÓRICA */
    /* Necesario porque la Vista no expone los IDs de usuario creador por defecto.
       Vamos a las tablas físicas para recuperar quién creó cada versión antigua. */
    LEFT JOIN `PICADE`.`DatosCapacitaciones` `H_DC` 
        ON `H_VC`.`Id_Detalle_de_Capacitacion` = `H_DC`.`Id_DatosCap`
    LEFT JOIN `PICADE`.`Usuarios` `H_U`             
        ON `H_DC`.`Fk_Id_Usuario_DatosCap_Created_by` = `H_U`.`Id_Usuario`
    LEFT JOIN `PICADE`.`Info_Personal` `H_IP`       
        ON `H_U`.`Fk_Id_InfoPersonal` = `H_IP`.`Id_InfoPersonal`
    
    /* FILTRO DE AGRUPACIÓN: Trae a todos los registros vinculados al mismo PADRE descubierto en el Bloque 1 */
    WHERE `H_VC`.`Id_Capacitacion` = v_Id_Padre_Capacitacion 
    
    /* ORDENAMIENTO: Cronológico Inverso (Lo más reciente arriba) para lectura natural */
    ORDER BY `H_VC`.`Id_Detalle_de_Capacitacion` DESC;

END$$

DELIMITER ;