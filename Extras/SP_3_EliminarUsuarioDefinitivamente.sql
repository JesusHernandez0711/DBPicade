/* ============================================================================================
   PROCEDIMIENTO: SP_EliminarUsuarioDefinitivamente
   ============================================================================================

   --------------------------------------------------------------------------------------------
   I. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   --------------------------------------------------------------------------------------------
   [QUÉ ES]: 
   Constituye el mecanismo de "Destrucción Física" (Hard Delete) dentro de la arquitectura 
   del sistema. A diferencia de la "Baja Lógica" (Switch Activo/Inactivo), este procedimiento 
   ejecuta sentencias `DELETE` que eliminan permanentemente los bits de información de los 
   platos del disco duro, liberando espacio y referencias de integridad.

   [CASO DE USO EXCLUSIVO - "DATA HYGIENE"]: 
   Este SP está diseñado estrictamente para la "Corrección de Errores Administrativos Inmediatos".
   Ejemplo: "El Administrador creó un usuario duplicado por error de dedo hace 5 minutos, 
   se dio cuenta del error, y necesita borrarlo totalmente para volver a capturarlo limpio".
   
   [ADVERTENCIA OPERATIVA]: 
   BAJO NINGUNA CIRCUNSTANCIA debe utilizarse para gestionar despidos, renuncias o jubilaciones. 
   Si un empleado deja la empresa, su expediente constituye un activo legal que DEBE conservarse 
   por razones de auditoría laboral. Para esos casos es obligatorio usar `SP_CambiarEstatusUsuario`.

   --------------------------------------------------------------------------------------------
   II. ARQUITECTURA DE SEGURIDAD E INTEGRIDAD (THE SAFETY NET)
   --------------------------------------------------------------------------------------------
   [RN-01] PROTOCOLO ANTI-SUICIDIO (SELF-DESTRUCTION PREVENTION):
      - Principio: "El sistema debe protegerse contra errores humanos catastróficos".
      - Regla: Un usuario autenticado no puede ejecutar este SP contra su propio ID 
        (`_Id_Admin_Ejecutor` != `_Id_Usuario_Objetivo`).
      - Impacto: Previene que un administrador se elimine a sí mismo accidentalmente, lo que 
        podría dejar al sistema acéfalo.

   [RN-02] ANÁLISIS FORENSE DE INSTRUCTOR (OPERATIONAL FOOTPRINT):
      - Validación: Antes de permitir el borrado, el sistema realiza un escaneo profundo en la 
        tabla `DatosCapacitaciones`.
      - Regla: Si el usuario aparece como `Fk_Id_Instructor` en CUALQUIER curso (Pasado, 
        Presente o Futuro), la eliminación se bloquea inmediatamente con Error 409.
      - Justificación: Borrar al instructor dejaría "cursos huérfanos" en los reportes históricos,
        donde un curso aparecería sin responsable asignado, rompiendo la integridad del historial.

   [RN-03] ANÁLISIS FORENSE DE PARTICIPANTE (ACADEMIC FOOTPRINT):
      - Validación: El sistema escanea la tabla `Capacitaciones_Participantes`.
      - Regla: Si el usuario tiene registros de asistencia o calificación, se bloquea.
      - Justificación: Es ilegal destruir evidencia de capacitación de un empleado (Auditoría STPS).
        Un kárdex académico es un documento legal que debe persistir más allá de la vida laboral.

   --------------------------------------------------------------------------------------------
   III. ESPECIFICACIÓN TÉCNICA (DATABASE ARCHITECTURE)
   --------------------------------------------------------------------------------------------
   - TIPO: Transacción ACID Destructiva.
   - ESTRATEGIA DE CONCURRENCIA: Se utiliza `SELECT ... FOR UPDATE` para adquirir un bloqueo 
     exclusivo (X-LOCK) sobre el registro objetivo al inicio de la transacción. Esto evita 
     "Condiciones de Carrera" donde otro proceso podría intentar asignar un curso al usuario 
     mientras este está siendo eliminado.
   
   - ORDEN DE EJECUCIÓN (CASCADE LOGIC):
      Debido a la restricción de llave foránea (`Fk_Id_InfoPersonal` dentro de la tabla `Usuarios`),
      el borrado debe seguir un orden quirúrgico para evitar errores de Constraint `ON DELETE NO ACTION`:
        1. Eliminar Entidad Hija (`Usuarios`) -> Libera la referencia FK.
        2. Eliminar Entidad Padre (`Info_Personal`) -> Borra el dato demográfico.
   ============================================================================================ */

DELIMITER $$

-- DROP PROCEDURE IF EXISTS `SP_EliminarUsuarioDefinitivamente`$$

CREATE PROCEDURE `SP_EliminarUsuarioDefinitivamente`(
    /* -----------------------------------------------------------------
       PARÁMETROS DE ENTRADA
       ----------------------------------------------------------------- */
    IN _Id_Admin_Ejecutor    INT,   -- [AUDITOR] Quién ordena la ejecución (Para logs de aplicación)
    IN _Id_Usuario_Objetivo  INT    -- [TARGET] El usuario a eliminar físicamente
)
THIS_PROC: BEGIN
    
    /* ========================================================================================
       BLOQUE 0: VARIABLES DE DIAGNÓSTICO Y CONTEXTO
       Propósito: Inicializar contenedores en memoria para realizar el análisis forense 
       antes de proceder con cualquier operación destructiva.
       ======================================================================================== */
    
    /* Punteros de Relación para el borrado en cascada */
    DECLARE v_Id_InfoPersonal INT DEFAULT NULL; -- ID de la tabla padre (Info_Personal)
    DECLARE v_Ficha_Objetivo  VARCHAR(50);      -- Dato visual para el mensaje de éxito
    DECLARE v_Existe          INT;              -- Bandera de existencia del registro
    
    /* Banderas de Análisis Forense (Semáforos de Integridad) */
    /* Si estas variables dejan de ser NULL, significa que el usuario tiene "Ataduras" */
    DECLARE v_Es_Instructor   INT DEFAULT NULL;
    DECLARE v_Es_Participante INT DEFAULT NULL;

    /* ========================================================================================
       BLOQUE 1: GESTIÓN DE EXCEPCIONES (HANDLERS)
       Propósito: Garantizar la Atomicidad. Si algo falla a mitad del borrado, el sistema 
       debe regresar al estado exacto anterior.
       ======================================================================================== */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
        ROLLBACK; 
        RESIGNAL; -- Propagar el error original al Backend para debugging
    END;

    /* ========================================================================================
       BLOQUE 2: VALIDACIONES PREVIAS (FAIL FAST)
       Propósito: Validar la integridad de la petición antes de consumir recursos de BD.
       ======================================================================================== */
    
    /* 2.1 Integridad de Inputs */
    IF _Id_Usuario_Objetivo IS NULL OR _Id_Usuario_Objetivo <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR DE SISTEMA [400]: ID de usuario inválido.';
    END IF;

    /* 2.2 Protección Anti-Suicidio (Seguridad Básica) 
       [RN-01] Un usuario no puede eliminarse a sí mismo. */
    IF _Id_Admin_Ejecutor = _Id_Usuario_Objetivo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ACCIÓN DENEGADA [403]: No puedes eliminarte a ti mismo. Por seguridad, pide a otro administrador que realice esta acción.';
    END IF;

    /* ========================================================================================
       BLOQUE 3: INSPECCIÓN Y BLOQUEO (FORENSIC ANALYSIS)
       Propósito: "Congelar" al usuario y verificar si tiene ataduras históricas antes de borrar.
       ======================================================================================== */
    START TRANSACTION;

    /* ----------------------------------------------------------------------------------------
       PASO 3.1: ADQUISICIÓN DE SNAPSHOT Y CANDADO DE ESCRITURA (X-LOCK)
       - Buscamos al usuario.
       - FOR UPDATE: Bloqueamos la fila. Nadie puede editar, asignar cursos o borrar a este 
         usuario hasta que terminemos el análisis.
       ---------------------------------------------------------------------------------------- */
    SELECT 
        1, 
        `Fk_Id_InfoPersonal`, 
        `Ficha`
    INTO 
        v_Existe, 
        v_Id_InfoPersonal, 
        v_Ficha_Objetivo
    FROM `Usuarios`
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo
    FOR UPDATE;

    /* Validación de Existencia */
    IF v_Existe IS NULL THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ERROR [404]: El usuario no existe o ya fue eliminado.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.2: ANÁLISIS FORENSE DE INSTRUCTOR (Operational Trace) [RN-02]
       Objetivo: Verificar si el usuario ha impartido capacitación alguna vez.
       Lógica: Escaneo en `DatosCapacitaciones`. Si existe 1 registro, es intocable.
       ---------------------------------------------------------------------------------------- */
    SELECT 1 INTO v_Es_Instructor
    FROM `DatosCapacitaciones`
    WHERE `Fk_Id_Instructor` = _Id_Usuario_Objetivo
    LIMIT 1;

    IF v_Es_Instructor IS NOT NULL THEN
        ROLLBACK; -- Liberamos el bloqueo inmediatamente
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar. Este usuario figura como INSTRUCTOR en el historial de capacitaciones. La eliminación rompería la integridad de los reportes. Use la opción "Desactivar" para archivar el expediente.';
    END IF;

    /* ----------------------------------------------------------------------------------------
       PASO 3.3: ANÁLISIS FORENSE DE PARTICIPANTE (Academic Trace) [RN-03]
       Objetivo: Verificar si el usuario tiene historial académico.
       Lógica: Escaneo en `Capacitaciones_Participantes`. Si tiene asistencia/calificación, es intocable.
       ---------------------------------------------------------------------------------------- */
    SELECT 1 INTO v_Es_Participante
    FROM `Capacitaciones_Participantes`
    WHERE `Fk_Id_Usuario` = _Id_Usuario_Objetivo
    LIMIT 1;

    IF v_Es_Participante IS NOT NULL THEN
        ROLLBACK; -- Liberamos el bloqueo inmediatamente
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'BLOQUEO DE INTEGRIDAD [409]: Imposible eliminar. Este usuario tiene historial académico como PARTICIPANTE (Calificaciones/Asistencia). Es ilegal destruir esta evidencia. Use la opción "Desactivar".';
    END IF;

    /* ========================================================================================
       BLOQUE 4: EJECUCIÓN DESTRUCTIVA (HARD DELETE SEQUENCE)
       Si el flujo llega a este punto, el análisis forense determinó que el usuario está "Limpio"
       (no tiene historial operativo ni académico). Es seguro proceder.
       ======================================================================================== */
    
    /* ----------------------------------------------------------------------------------------
       PASO 4.1: ELIMINAR CUENTA DE USUARIO (ENTIDAD HIJA)
       Acción: Borramos primero la tabla `Usuarios`.
       Razón Técnica: Esta tabla tiene la llave foránea `Fk_Id_InfoPersonal`. Debemos romper 
       este vínculo antes de poder borrar al "Padre" (`Info_Personal`).
       ---------------------------------------------------------------------------------------- */
    DELETE FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Objetivo;

    /* ----------------------------------------------------------------------------------------
       PASO 4.2: ELIMINAR DATOS PERSONALES (ENTIDAD PADRE)
       Acción: Borramos el registro en `Info_Personal`.
       Condición: Solo si existía un vínculo (v_Id_InfoPersonal NOT NULL).
       Resultado: El expediente ha sido purgado completamente.
       ---------------------------------------------------------------------------------------- */
    IF v_Id_InfoPersonal IS NOT NULL THEN
        DELETE FROM `Info_Personal` 
        WHERE `Id_InfoPersonal` = v_Id_InfoPersonal;
    END IF;

    /* ========================================================================================
       BLOQUE 5: CONFIRMACIÓN FINAL
       Propósito: Hacer permanentes los cambios y notificar al usuario.
       ======================================================================================== */
    COMMIT;

    /* Feedback de éxito estructurado para el Frontend */
    SELECT 
        CONCAT('ELIMINACIÓN EXITOSA: El usuario con Ficha ', v_Ficha_Objetivo, ' y todos sus datos asociados han sido borrados permanentemente del sistema.') AS Mensaje,
        _Id_Usuario_Objetivo AS Id_Eliminado,
        'ELIMINADO' AS Accion;

END$$

DELIMITER ;