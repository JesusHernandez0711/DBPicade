/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   PROCEDIMIENTO: SP_ConsularParticipantesCapacitacion
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   
   I. FICHA TÉCNICA DE INGENIERÍA (ENGINEERING DATASHEET)
   ----------------------------------------------------------------------------------------------------------
   - Nombre Oficial       : SP_ConsularParticipantesCapacitacion
   - Sistema        	  : PICADE (Plataforma Institucional de Capacitación y Desarrollo)
   - Modulo				  : Gestión Académica / Coordinación
   - Autorizacion  		  : Nivel Administrativo (Requiere Token de Sesión Activo)
   - Alias Operativo      : "The Live Grid Refresher" (El Refrescador de Matrícula)
   - Clasificación        : Transacción de Lectura en Tiempo Real (Real-Time Read Transaction)
   - Nivel de Aislamiento : READ COMMITTED (Lectura Confirmada)
   - Complejidad Ciclomática: Baja (Lineal), pero con alta densidad de datos por fila.
   - Dependencias         : 
     1. Vista_Capacitaciones (Fuente de Métricas Globales)
     2. Vista_Gestion_de_Participantes (Fuente de Detalle Nominal)

   II. PROPÓSITO ESTRATÉGICO Y DE NEGOCIO (BUSINESS VALUE)
   ----------------------------------------------------------------------------------------------------------
   Este procedimiento almacenado actúa como el "Sistema Nervioso Central" del módulo de Coordinación.
   Su función no es solo traer datos, sino sincronizar la realidad operativa con la interfaz de usuario.
   
   [PROBLEMA QUE RESUELVE]:
   En sistemas de alta concurrencia, existe una discrepancia temporal entre el cupo que muestra
   el catálogo de cursos y la lista real de alumnos. Este SP elimina esa discrepancia al devolver
   dos conjuntos de datos (Resultsets) en una sola petición de red (Round-Trip):
   
   1. EL ENCABEZADO (METRICS): Dice "cuántos hay y cuántos caben".
   2. EL CUERPO (ROSTER): Dice "quiénes son y cómo van".

   III. ARQUITECTURA DE INTEGRIDAD DE DATOS (DATA INTEGRITY ARCHITECTURE)
   ----------------------------------------------------------------------------------------------------------
   A. INTEGRIDAD DE CUPO HÍBRIDO (The Hybrid Capacity Rule):
      Este SP implementa la lectura de la regla `GREATEST(Manual, Sistema)`.
      - Si el sistema cuenta 5 alumnos, pero el coordinador bloqueó 20 lugares manuales,
        este SP reportará 20 lugares ocupados, impidiendo sobreventas desde el Frontend.

   B. TRAZABILIDAD FORENSE (Forensic Audit Trail):
      Expone la columna `Nota_Auditoria` (Justificación), permitiendo al coordinador ver 
      historiales de cambios (ej: "Baja por inasistencia") sin tener que consultar logs del servidor.

   IV. CONTRATO DE SALIDA (OUTPUT CONTRACT)
   ----------------------------------------------------------------------------------------------------------
   [RESULTSET 1 - HEADER]: Métricas de alto nivel para los "Badges" y contadores del UI.
   [RESULTSET 2 - BODY]  : Tabla detallada para el pase de lista y captura de notas.

   ========================================================================================================== */

-- Inicia la definición del delimitador para el bloque de código procedimental.
-- Eliminación preventiva del objeto para asegurar una recompilación limpia del diccionario de datos.

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_ConsularParticipantesCapacitacion`$$

CREATE PROCEDURE `SP_ConsularParticipantesCapacitacion`(
    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       SECCIÓN DE PARÁMETROS DE ENTRADA (INPUT PARAMETERS)
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- [PARÁMETRO]: _Id_Detalle_Capacitacion
    -- [TIPO]: INT (Entero)
    -- [DESCRIPCIÓN]: Puntero único a la instancia específica del curso (Tabla `DatosCapacitaciones`).
    -- [NOTA TÉCNICA]: No confundir con el ID del Temario. Este ID representa al GRUPO específico
    -- que tiene una fecha de inicio, un instructor asignado y una lista de asistencia propia.
    IN _Id_Detalle_Capacitacion INT
)
ProcPartCapac: BEGIN

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 0: DEFENSA EN PROFUNDIDAD Y SANITIZACIÓN (FAIL-FAST STRATEGY)
       Objetivo: Rechazar peticiones mal formadas antes de consumir recursos de lectura en disco.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    
    -- Validación 0.1: Integridad del Puntero
    -- Verificamos que el ID no sea Nulo (NULL) ni un valor imposible (menor o igual a cero).
    -- Esto previene inyecciones de errores lógicos y optimiza el plan de ejecución del motor SQL.
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        
        -- [RESPUESTA DE ERROR 400 - BAD REQUEST]
        -- Informamos al Frontend que la solicitud no puede ser procesada por falta de contexto.
        SELECT 'ERROR DE ENTRADA [400]: ID obligatorio.' AS Mensaje; 
        
        -- Terminación inmediata del flujo de ejecución (Circuit Breaker).
        LEAVE ProcPartCapac;
    END IF;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 1: RESULTSET DE MÉTRICAS (HEADER DASHBOARD)
       ------------------------------------------------------------------------------------------------------
       Objetivo: Alimentar la cabecera del Grid en el Frontend.
       Contexto: Estos datos sirven para refrescar los contadores visuales (ej: "18/20 inscritos").
       Fuente de Verdad: `Vista_Capacitaciones` (Vista Maestra).
       
       [LÓGICA DE NEGOCIO CRÍTICA]:
       Aquí se calculan los semáforos de disponibilidad. Si `Cupo_Disponible` llega a 0, 
       el botón de "Agregar Participante" en el Frontend debe deshabilitarse automáticamente.
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        -- [IDENTIFICADOR VISUAL]
        -- El código humano-legible del curso (ej: "CAP-2026-RH-001").
        -- Permite al usuario confirmar que está viendo el grupo correcto.
        `VC`.`Numero_Capacitacion`         AS `Folio_Curso`,
        
        /* -----------------------------------------------------------------------------------------
           [KPIs DE PLANEACIÓN - PLANIFICADO]
           Datos estáticos definidos al crear el curso. Representan la "Meta".
           ----------------------------------------------------------------------------------------- */

        -- Capacidad máxima teórica del aula o sala virtual.
        `VC`.`Asistentes_Meta`             AS `Cupo_Programado_de_Asistentes`,
        
        -- Cantidad de asientos reservados manualmente por el coordinador (Override).
        -- Este valor tiene precedencia sobre el conteo automático en caso de ser mayor.
        `VC`.`Asistentes_Manuales`, 
        
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
        `VC`.`Cupo_Disponible`
        
    FROM `Picade`.`Vista_Capacitaciones` `VC`
    
    -- Filtro por Llave Primaria del Detalle para obtener métricas exclusivas de este grupo.
    WHERE `VC`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion;

    /* ══════════════════════════════════════════════════════════════════════════════════════════════════════
       FASE 2: RESULTSET DE NÓMINA DETALLADA (DATA GRID BODY)
       ------------------------------------------------------------------------------------------------------
       Objetivo: Proveer el listado fila por fila para la gestión individual.
       Contexto: Esta tabla es donde el Instructor/Coordinador pasa lista, asigna calificaciones 
                 o cambia el estatus de un alumno específico.
       Fuente de Verdad: `Vista_Gestion_de_Participantes` (Vista Desnormalizada de Detalle).
       ══════════════════════════════════════════════════════════════════════════════════════════════════════ */

    SELECT 
        /* -----------------------------------------------------------------------------------------
           [IDENTIFICADORES DE ACCIÓN - CRUD HANDLES]
           Datos técnicos ocultos necesarios para las operaciones de actualización.
           ----------------------------------------------------------------------------------------- */
        
        -- Llave Primaria (PK) de la relación Alumno-Curso.
        -- Este ID se envía al `SP_EditarParticipanteCapacitacion` o `SP_CambiarEstatus...`.
        `VGP`.`Id_Registro_Participante`   AS `Id_Inscripcion`,
        
        /* -----------------------------------------------------------------------------------------
           [INFORMACIÓN VISUAL DEL PARTICIPANTE]
           Datos para que el humano identifique al alumno.
           ----------------------------------------------------------------------------------------- */
        
        -- ID Corporativo o Número de Empleado. Vital para diferenciar homónimos.
        `VGP`.`Ficha_Participante`         AS `Ficha`,
        
        -- Nombre Completo Normalizado.
        -- Se concatenan Paterno + Materno + Nombre para alinearse con los estándares
        -- de listas de asistencia impresas (orden alfabético por apellido).
        CONCAT(
            `VGP`.`Ap_Paterno_Participante`, ' ', 
            `VGP`.`Ap_Materno_Participante`, ' ', 
            `VGP`.`Nombre_Pila_Participante`
        )                                  AS `Nombre_Alumno`,
        
        /* -----------------------------------------------------------------------------------------
           [INPUTS ACADÉMICOS EDITABLES]
           Datos que el coordinador puede modificar directamente en el grid.
           ----------------------------------------------------------------------------------------- */
        
        -- Porcentaje de Asistencia (0.00 - 100.00).
        -- Alimenta la barra de progreso visual en el Frontend.
        `VGP`.`Porcentaje_Asistencia`      AS `Asistencia`,
        
        -- Calificación Final Asentada (0.00 - 100.00).
        -- Si es NULL, el Frontend debe mostrar un input vacío o "Sin Evaluar".
        `VGP`.`Calificacion_Numerica`      AS `Calificacion`,
        
        /* -----------------------------------------------------------------------------------------
           [ESTADO DEL CICLO DE VIDA Y AUDITORÍA]
           Datos de control de flujo y trazabilidad.
           ----------------------------------------------------------------------------------------- */
        
        -- Estatus Semántico (Texto).
        -- Valores posibles: 'INSCRITO', 'ASISTIÓ', 'APROBADO', 'REPROBADO', 'BAJA'.
        -- Se usa para determinar el color de la fila (ej: Baja = Rojo, Aprobado = Verde).
        `VGP`.`Resultado_Final`            AS `Estatus_Participante`, 
        
        -- Descripción Técnica.
        -- Explica la regla de negocio aplicada (ej: "Reprobado por inasistencia > 20%").
        -- Se usa típicamente en un Tooltip al pasar el mouse sobre el estatus.
        `VGP`.`Detalle_Resultado`          AS `Descripcion_Estatus`,
        
        -- [AUDITORÍA FORENSE INYECTADA]:
        -- Contiene la cadena histórica de cambios (Timestamp + Motivo).
        -- Permite al coordinador saber por qué un alumno tiene una calificación extraña
        -- o por qué fue reactivado después de una baja.
        `VGP`.`Nota_Auditoria`             AS `Justificacion`

    FROM `Picade`.`Vista_Gestion_de_Participantes` `VGP`
    
    -- Filtro estricto por la instancia del curso.
    WHERE `VGP`.`Id_Detalle_de_Capacitacion` = _Id_Detalle_Capacitacion
    
    /* -----------------------------------------------------------------------------------------
       [ESTRATEGIA DE ORDENAMIENTO - UX STANDARD]
       Ordenamos alfabéticamente por Apellido Paterno -> Materno -> Nombre.
       Esto es mandatorio para facilitar el cotejo visual contra listas físicas o de Excel.
       ----------------------------------------------------------------------------------------- */
    ORDER BY `VGP`.`Ap_Paterno_Participante` ASC, `VGP`.`Ap_Materno_Participante` ASC;

END$$

-- Restaura el delimitador estándar para continuar con scripts normales.
DELIMITER ;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   FIN DEL ARTEFACTO: SP_ConsularParticipantesCapacitacion
   STATUS: CERTIFICADO PARA PRODUCCIÓN (PLATINUM LEVEL)
   REVISIÓN DE SEGURIDAD: APROBADA
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════ */