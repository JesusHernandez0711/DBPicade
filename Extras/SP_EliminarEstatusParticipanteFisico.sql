/* ====================================================================================================
   PROCEDIMIENTOS: SP_EliminarEstatusParticipanteFisico (Hard Delete / Purga)
   ====================================================================================================

   ----------------------------------------------------------------------------------------------------
   I. MANIFIESTO DE SEGURIDAD Y PROPÓSITO (THE SAFETY MANIFESTO)
   ----------------------------------------------------------------------------------------------------
   [DEFINICIÓN DEL COMPONENTE]:
   Este procedimiento almacenado implementa el mecanismo de **Eliminación Física** (`DELETE`) para un 
   registro del catálogo `Cat_Estatus_Participante`. A diferencia de la desactivación lógica 
   (`SP_CambiarEstatus`), esta operación elimina los bits de datos del disco duro de manera permanente. 
   No existe posibilidad de recuperación ("Rollback") una vez confirmado el `COMMIT`.

   [CASO DE USO LEGÍTIMO - "DATA HYGIENE"]:
   Esta herramienta está diseñada EXCLUSIVAMENTE para la **Corrección de Errores de Captura Inmediata** (Saneamiento de Datos).
   
   * Escenario Válido: El administrador crea el estatus "Aprovado" (con error ortográfico). Se da cuenta 
     al instante (T < 1 min). Nadie lo ha usado aún. En lugar de desactivarlo y dejar "basura" en la BD, 
     se utiliza este SP para purgarlo y mantener el catálogo impoluto.

   [LA REGLA DE "CERO TOLERANCIA" (ZERO TOLERANCE POLICY)]:
   Para garantizar la Integridad Referencial Dura (Hard Referential Integrity), este SP aplica la regla 
   más estricta del sistema de bases de datos relacionales:
   
   > "Un Padre no puede ser eliminado si tiene siquiera un Hijo, vivo, muerto o archivado."

   [DIFERENCIA CRÍTICA CON SOFT DELETE]:
   - Soft Delete: Permite apagar un estatus si el curso ya terminó. (Preserva la historia).
   - Hard Delete: Bloquea la eliminación si existe CUALQUIER registro histórico. (Protege la integridad).
   
   No importa si el curso donde se usó está "Activo", "Cancelado", "Finalizado" o "Archivado". 
   Si existe una sola fila en la tabla `Capacitaciones_Participantes` vinculada a este estatus, 
   la eliminación se bloquea. Borrarlo rompería la llave foránea (FK) y corrompería el historial 
   académico de los participantes.

   ----------------------------------------------------------------------------------------------------
   II. MATRIZ DE REGLAS DE BLINDAJE (DESTRUCTIVE RULES MATRIX)
   ----------------------------------------------------------------------------------------------------
   [RN-01] VERIFICACIÓN DE EXISTENCIA PREVIA (FAIL FAST PATTERN):
      - Principio: "No intentar matar lo que ya está muerto".
      - Mecanismo: Validamos que el registro exista antes de intentar borrarlo.
      - Beneficio: Permite devolver un error 404 (Not Found) preciso, en lugar de un mensaje genérico 
        de "0 filas afectadas".

   [RN-02] BLOQUEO DE RECURSO (PESSIMISTIC CONCURRENCY LOCK):
      - Principio: "Aislamiento Serializable".
      - Mecanismo: Se adquiere un bloqueo exclusivo (`FOR UPDATE`) sobre la fila a borrar al inicio 
        de la transacción.
      - Justificación: Esto evita la "Condición de Carrera" (Race Condition) donde el Usuario A 
        intenta borrar el estatus mientras el Usuario B le asigna un alumno en el mismo milisegundo.

   [RN-03] ESCANEO DE DEPENDENCIAS TOTALES (TOTAL FORENSIC SCAN):
      - Principio: "Integridad sobre Conveniencia".
      - Mecanismo: Se consulta `Capacitaciones_Participantes` sin filtros de estado.
      - Condición: `COUNT(*) > 0`.
      - Acción: Si se encuentra cualquier uso (histórico o actual), se aborta con Error 409.
      
   [RN-04] PROTECCIÓN DE MOTOR (LAST LINE OF DEFENSE):
      - Principio: "Defensa en Profundidad".
      - Mecanismo: Si fallara la validación lógica manual (RN-03), el `HANDLER 1451` captura el error 
        nativo de Foreign Key de MySQL.
      - Beneficio: Evita que el usuario final vea errores técnicos crípticos del motor SQL.

   ----------------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA (TECHNICAL SPECS)
   ----------------------------------------------------------------------------------------------------
   - INPUT: `_Id_Estatus` (INT).
   - OUTPUT: JSON { Mensaje, Accion, Id_Eliminado }.
   - LOCKING STRATEGY: `X-Lock` (Exclusive Row Lock) via InnoDB.
   - ISOLATION LEVEL: Read Committed (por defecto) elevado a Serializable para la fila objetivo.
   ==================================================================================================== */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarEstatusParticipanteFisico`$$

CREATE PROCEDURE `SP_EliminarEstatusParticipanteFisico`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA (INPUT LAYER)
       Recibe el identificador atómico del recurso a destruir.
       ----------------------------------------------------------------- */
    IN _Id_Estatus INT -- [OBLIGATORIO] ID único (PK) del estatus a purgar.
)
THIS_PROC: BEGIN
    
    /* ============================================================================================
       SECCIÓN A: DECLARACIÓN DE VARIABLES Y CONTEXTO (VARIABLE SCOPE)
       Inicialización de contenedores de memoria para el diagnóstico forense.
       ============================================================================================ */
    
    /* [Variable de Evidencia]: 
       Almacena el nombre del registro antes de borrarlo. 
       Se usa para confirmar al usuario QUÉ fue lo que eliminó en el mensaje de éxito. */
    DECLARE v_Nombre_Actual VARCHAR(255);
    
    /* [Semáforo de Integridad]: 
       Variable crítica. Almacena el conteo de referencias encontradas en tablas hijas.
       Si > 0, es un bloqueo absoluto. */
    DECLARE v_Dependencias_Totales INT DEFAULT 0;
    
    /* [Buffer de Mensajería]: 
       Para construir mensajes de error dinámicos y detallados en tiempo de ejecución. */
    DECLARE v_Mensaje_Error TEXT;

    /* ============================================================================================
       SECCIÓN B: HANDLERS DE SEGURIDAD (EXCEPTION HANDLING LAYER)
       Configuración de la "Red de Seguridad" para atrapar errores del motor de base de datos.
       ============================================================================================ */
    
    /* [B.1] Handler de Integridad Referencial (Error MySQL 1451)
       OBJETIVO: Actuar como "Paracaídas". 
       ESCENARIO: Si agregamos una nueva tabla en el futuro que use este estatus y olvidamos 
       actualizar la validación manual de este SP, el motor bloqueará el DELETE.
       ACCIÓN: Este handler atrapa ese bloqueo técnico y devuelve un mensaje humano. */
    DECLARE EXIT HANDLER FOR 1451 
    BEGIN 
        ROLLBACK; -- Deshacer transacción inmediatamente.
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE SISTEMA [1451]: La base de datos impidió la eliminación porque existen vínculos en tablas del sistema no detectados por la lógica de negocio (Integridad Referencial).'; 
    END;

    /* [B.2] Handler Genérico (SQLEXCEPTION)
       OBJETIVO: Capturar fallos de infraestructura (Disco lleno, Timeout, Conexión caída). */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Propagar el error original al backend para logs de sistema.
    END;

    /* ============================================================================================
       SECCIÓN C: VALIDACIONES PREVIAS (FAIL FAST STRATEGY)
       Filtrado de peticiones inválidas antes de iniciar transacciones costosas.
       ============================================================================================ */
    
    /* [C.1] Validación de Integridad de Entrada (Type Safety)
       Asegura que el ID sea un número positivo. */
    IF _Id_Estatus IS NULL OR _Id_Estatus <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID de Estatus inválido o nulo. Verifique la petición.';
    END IF;

    /* ============================================================================================
       SECCIÓN D: INICIO DE TRANSACCIÓN Y BLOQUEO (ACID TRANSACTION START)
       A partir de aquí, las operaciones son atómicas y aisladas.
       ============================================================================================ */
    START TRANSACTION;

    /* --------------------------------------------------------------------------------------------
       PASO D.1: IDENTIFICACIÓN Y BLOQUEO PESIMISTA (PESSIMISTIC LOCKING)
       
       
       [ESTRATEGIA TÉCNICA]:
       Ejecutamos `SELECT ... FOR UPDATE`.
       
       [IMPACTO EN EL MOTOR]:
       InnoDB adquiere un "Exclusive Lock (X)" sobre la fila específica en el índice primario.
       
       [JUSTIFICACIÓN DE NEGOCIO]:
       Estamos "secuestrando" el registro. Mientras esta transacción esté viva, nadie más puede:
         1. Asignar este estatus a un alumno (INSERT en tabla hija).
         2. Modificar este estatus (UPDATE).
         3. Borrar este estatus (DELETE concurrente).
       Esto garantiza que nuestro escaneo de dependencias sea válido hasta el final.
       -------------------------------------------------------------------------------------------- */
    SELECT `Nombre` INTO v_Nombre_Actual
    FROM `Cat_Estatus_Participante`
    WHERE `Id_CatEstPart` = _Id_Estatus
    LIMIT 1
    FOR UPDATE;

    /* [D.2] Validación de Existencia (404 Check)
       Si la variable sigue siendo NULL, el registro no existe físicamente. */
    IF v_Nombre_Actual IS NULL THEN
        ROLLBACK; -- Liberar recursos.
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE NEGOCIO [404]: El Estatus no existe o ya fue eliminado previamente.';
    END IF;

    /* ============================================================================================
       SECCIÓN E: ESCANEO DE DEPENDENCIAS (LA REGLA DE CERO TOLERANCIA)
       Aquí reside la diferencia crítica con el Soft Delete.
       ============================================================================================ */
    
    /* --------------------------------------------------------------------------------------------
       PASO E.1: CONSULTA DE USO HISTÓRICO TOTAL (FORENSIC SCAN)
       
       [ANÁLISIS DE LA CONSULTA]:
       1. TARGET: Tabla `Capacitaciones_Participantes` (La tabla de hechos).
       2. FILTRO: `Fk_Id_CatEstPart` = ID Objetivo.
       3. SCOPE: **GLOBAL**. 
          - NO hacemos JOIN con `DatosCapacitaciones`.
          - NO preguntamos si el curso está activo (`Activo=1`).
          - NO preguntamos si el curso finalizó (`Es_Final=1`).
          - NO preguntamos si el curso fue borrado (`Activo=0`).
       
       [FILOSOFÍA]: "Si existe un registro hijo, el padre es inmortal".
       Incluso si el curso fue borrado hace 10 años, la integridad referencial física de la BD 
       exige que la llave foránea apunte a algo existente. Borrar el padre dejaría un "Hijo Huérfano"
       o rompería el constraint físico.
       -------------------------------------------------------------------------------------------- */
    SELECT COUNT(*) INTO v_Dependencias_Totales
    FROM `Capacitaciones_Participantes`
    WHERE `Fk_Id_CatEstPart` = _Id_Estatus;

    /* --------------------------------------------------------------------------------------------
       PASO E.2: EVALUACIÓN DE BLOQUEO (DECISION GATE)
       Si el contador es > 0, se activa el protocolo de rechazo.
       -------------------------------------------------------------------------------------------- */
    IF v_Dependencias_Totales > 0 THEN
        
        ROLLBACK; -- Liberar el bloqueo y cancelar la transacción inmediatamente.
        
        /* Construcción del Mensaje Humano:
           Explicamos claramente al usuario la razón técnica del bloqueo. */
        SET v_Mensaje_Error = CONCAT(
            'BLOQUEO DE INTEGRIDAD REFERENCIAL [409]: Operación Denegada. ',
            'No es posible ELIMINAR FÍSICAMENTE el estatus "', v_Nombre_Actual, '". ',
            'El sistema detectó ', v_Dependencias_Totales, ' registros históricos de participantes asociados a este estatus. ',
            'Nota Técnica: Aunque los cursos hayan finalizado, estén archivados o borrados, la integridad de la base de datos impide borrar un catálogo con historial. ',
            'SOLUCIÓN: Utilice la opción de "Desactivar" (Baja Lógica) en su lugar.'
        );
                               
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_Mensaje_Error;
    END IF;

    /* ============================================================================================
       SECCIÓN F: EJECUCIÓN DESTRUCTIVA (HARD DELETE EXECUTION)
       Si el flujo llega a este punto, hemos certificado que el registro está "limpio", "virgen" 
       y "solo". Es seguro proceder con la destrucción.
       ============================================================================================ */
    
    /* [F.1] Ejecución del Comando de Borrado
       Esta instrucción elimina la fila de la página de datos del disco. */
    DELETE FROM `Cat_Estatus_Participante`
    WHERE `Id_CatEstPart` = _Id_Estatus;

    /* ============================================================================================
       SECCIÓN G: CONFIRMACIÓN Y RESPUESTA (COMMIT & FEEDBACK)
       Finalización exitosa del protocolo.
       ============================================================================================ */
    
    /* [G.1] Confirmación de Transacción (COMMIT)
       Hacemos permanentes los cambios. 
       - El registro deja de existir.
       - El bloqueo (X-Lock) se libera.
       - El espacio en disco se marca como disponible. */
    COMMIT;

    /* [G.2] Respuesta Estructurada al Frontend
       Devolvemos un objeto JSON-like para que la UI pueda actualizarse (ej: quitar la fila de la tabla). */
    SELECT 
        CONCAT('ÉXITO: El Estatus "', v_Nombre_Actual, '" ha sido ELIMINADO permanentemente del sistema.') AS Mensaje,
        'ELIMINACION_FISICA_COMPLETA' AS Accion,
        _Id_Estatus AS Id_Estatus_Eliminado,
        NOW() AS Fecha_Ejecucion;

END$$

DELIMITER ;