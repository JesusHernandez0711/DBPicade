/* ======================================================================================================
   PROCEDIMIENTO: SP_Inscribir_Participante
   ======================================================================================================
   
   ------------------------------------------------------------------------------------------------------
   1. FICHA TÉCNICA (TECHNICAL DATASHEET)
   ------------------------------------------------------------------------------------------------------
   - Nombre Oficial:       SP_Inscribir_Participante
   - Tipo de Objeto:       Stored Procedure (Rutina Almacenada)
   - Clasificación:        Transacción de Escritura Crítica (Critical Write Transaction)
   - Nivel de Aislamiento: READ COMMITTED (Lectura Confirmada)
   - Dependencias:         Tablas: Usuarios, Capacitaciones_Participantes, DatosCapacitaciones, Capacitaciones.
                           Catálogos: Cat_Estatus_Capacitacion.
   
   ------------------------------------------------------------------------------------------------------
   2. VISIÓN DE NEGOCIO (BUSINESS LOGIC OVERVIEW)
   ------------------------------------------------------------------------------------------------------
   Este procedimiento actúa como el "Controlador de Acceso" (Gatekeeper) para las aulas.
   Su responsabilidad es garantizar la integridad referencial y de negocio antes de permitir
   que un usuario ocupe un asiento.
   
   [ALGORITMO DE CUPO HÍBRIDO - "PESIMISTA"]:
   Para evitar el sobrecupo, el sistema no confía ciegamente en el conteo automático.
   Implementa una comparación en tiempo real:
     A = Conteo de registros en BD (Automático).
     B = Cifra escrita manualmente por el coordinador (Manual/Override).
     Ocupados Reales = MAX(A, B).
   
   Esto asegura que si hay personas físicas en el aula que no han sido registradas en sistema,
   el coordinador puede bloquear esos espacios manualmente usando el campo 'AsistentesReales',
   y el SP respetará esa restricción.

   ------------------------------------------------------------------------------------------------------
   3. ARQUITECTURA DE DEFENSA (DEFENSE IN DEPTH)
   ------------------------------------------------------------------------------------------------------
   El código implementa 7 capas de validación secuencial (Fail-Fast Strategy):
     0. Sanitización: Rechazo inmediato de inputs nulos/inválidos.
     1. Autenticación: Verificación del ejecutor.
     2. Identidad: Verificación de la existencia y estatus del alumno.
     3. Contexto: Verificación de la vigencia del curso.
     4. Estado: Verificación de ciclo de vida (No inscribir en cursos cerrados).
     5. Unicidad: Prevención de duplicados (Idempotencia).
     6. Capacidad: Cálculo matemático de disponibilidad de asientos.

   ====================================================================================================== */

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Inscribir_Participante`$$

CREATE PROCEDURE `SP_Inscribir_Participante`(
    IN _Id_Usuario_Ejecutor INT,      -- [INPUT]: ID del usuario (Coordinador/Admin) que solicita la transacción.
    IN _Id_Detalle_Capacitacion INT,  -- [INPUT]: ID de la instancia específica del curso (Tabla: DatosCapacitaciones).
    IN _Id_Usuario_Participante INT   -- [INPUT]: ID del usuario (Alumno) que será inscrito.
)
ProcInsPart: BEGIN
    /* ═══════════════════════════════════════════════════════════════════════════════════
       BLOQUE DE DEFINICIÓN DE VARIABLES (MEMORY ALLOCATION)
       Nota: Todas las variables se inicializan en 0 o '' para evitar valores NULL incontrolados.
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- [FLAGS DE VALIDACIÓN]: Semáforos para verificar existencia en base de datos.
    DECLARE v_Ejecutor_Existe INT DEFAULT 0;
    DECLARE v_Participante_Existe INT DEFAULT 0;
    DECLARE v_Participante_Activo INT DEFAULT 0;
    
    -- [CONTEXTO DEL CURSO]: Variables para almacenar el estado actual de la capacitación.
    DECLARE v_Capacitacion_Existe INT DEFAULT 0;
    DECLARE v_Capacitacion_Activa INT DEFAULT 0;
    DECLARE v_Id_Capacitacion_Padre INT DEFAULT 0;  -- ID de la cabecera (Temario)
    DECLARE v_Folio_Curso VARCHAR(100) DEFAULT '';  -- Folio legible para mensajes de error
    DECLARE v_Estatus_Curso INT DEFAULT 0;          -- ID del estatus operativo actual
    DECLARE v_Es_Estatus_Final INT DEFAULT 0;       -- Bandera (1=Finalizado, 0=Abierto)
    
    -- [CÁLCULO DE CUPO]: Variables para la aritmética de asientos.
    DECLARE v_Cupo_Maximo INT DEFAULT 0;       -- Limite físico/lógico (Meta)
    DECLARE v_Conteo_Sistema INT DEFAULT 0;    -- Count(*) SQL real
    DECLARE v_Conteo_Manual INT DEFAULT 0;     -- Override manual del coordinador
    DECLARE v_Asientos_Ocupados INT DEFAULT 0; -- Resultado de GREATEST(Sistema, Manual)
    DECLARE v_Cupo_Disponible INT DEFAULT 0;   -- Resultado final (Meta - Ocupados)
    
    -- [CONTROL DE FLUJO]:
    DECLARE v_Ya_Inscrito INT DEFAULT 0;       -- Detección de duplicados
    DECLARE v_Nuevo_Id_Registro INT DEFAULT 0; -- ID generado tras el INSERT (Identity)
    
    -- [CONSTANTES DE NEGOCIO]: Mapeo duro de IDs de catálogo para evitar números mágicos en la lógica.
    DECLARE c_ESTATUS_INSCRITO INT DEFAULT 1; -- Cat_Estatus_Participante: Inscrito
    DECLARE c_ESTATUS_BAJA INT DEFAULT 5;     -- Cat_Estatus_Participante: Baja (Libera cupo)

    /* -----------------------------------------------------------------------------------
       MANEJO DE EXCEPCIONES (EXCEPTION HANDLING)
       Propósito: Garantizar atomicidad. Si algo falla, se revierte todo (ROLLBACK).
       ----------------------------------------------------------------------------------- */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK; -- [CRÍTICO]: Deshacer cualquier escritura parcial en disco.
        SELECT 
            'ERROR DE SISTEMA [500]: Fallo interno crítico durante la transacción de inscripción.' AS Mensaje,
            'ERROR_TECNICO' AS Accion,
            NULL AS Id_Registro_Participante;
    END;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 0: SANITIZACIÓN Y VALIDACIÓN DE INPUTS (FAIL-FAST)
       Objetivo: Detener la ejecución inmediatamente si los parámetros son inválidos.
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- Validar que el ejecutor no sea NULL ni Cero
    IF _Id_Usuario_Ejecutor IS NULL OR _Id_Usuario_Ejecutor <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Usuario Ejecutor es obligatorio.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;
    
    -- Validar que el curso destino no sea NULL ni Cero
    IF _Id_Detalle_Capacitacion IS NULL OR _Id_Detalle_Capacitacion <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID de la Capacitación es obligatorio.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;
    
    -- Validar que el alumno destino no sea NULL ni Cero
    IF _Id_Usuario_Participante IS NULL OR _Id_Usuario_Participante <= 0 THEN
        SELECT 'ERROR DE ENTRADA [400]: El ID del Participante es obligatorio.' AS Mensaje, 'VALIDACION_FALLIDA' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 1: VERIFICACIÓN DE CREDENCIALES DEL EJECUTOR
       Objetivo: Asegurar trazabilidad. Solo usuarios activos pueden ejecutar acciones.
       ═══════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*) INTO v_Ejecutor_Existe 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Ejecutor AND `Activo` = 1;
    
    IF v_Ejecutor_Existe = 0 THEN
        SELECT 'ERROR DE SEGURIDAD [403]: El Usuario Ejecutor no es válido o está inactivo.' AS Mensaje, 'ACCESO_DENEGADO' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 2: VERIFICACIÓN DE ELEGIBILIDAD DEL PARTICIPANTE
       Objetivo: Evitar inscribir usuarios inexistentes o dados de baja administrativamente.
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- Obtener existencia y estatus del usuario en una sola lectura
    SELECT COUNT(*), `Activo` 
    INTO v_Participante_Existe, v_Participante_Activo 
    FROM `Usuarios` 
    WHERE `Id_Usuario` = _Id_Usuario_Participante;
    
    -- Validación 2.1: Integridad Referencial
    IF v_Participante_Existe = 0 THEN
        SELECT 'ERROR DE INTEGRIDAD [404]: El usuario a inscribir no existe en el sistema.' AS Mensaje, 'RECURSO_NO_ENCONTRADO' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;
    
    -- Validación 2.2: Lógica de Negocio (Usuarios inactivos no pueden tomar cursos)
    IF v_Participante_Activo = 0 THEN
        SELECT 'ERROR DE LÓGICA [409]: El usuario está INACTIVO (Baja Administrativa). No puede ser inscrito.' AS Mensaje, 'CONFLICTO_ESTADO' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 3: CARGA DE CONTEXTO DEL CURSO (DATA SNAPSHOT)
       Objetivo: Cargar todos los datos necesarios del curso en memoria para evitar
       consultas repetitivas a la base de datos en fases posteriores (Performance).
       ═══════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        COUNT(*),                             -- [0] Verificador de existencia
        COALESCE(`DC`.`Activo`, 0),           -- [1] Verificador de borrado lógico
        `DC`.`Fk_Id_Capacitacion`,            -- [2] ID Padre para buscar Meta
        `DC`.`Fk_Id_CatEstCap`,               -- [3] Estatus actual para reglas de negocio
        COALESCE(`DC`.`AsistentesReales`, 0)  -- [4] INPUT MANUAL para algoritmo híbrido
    INTO 
        v_Capacitacion_Existe, 
        v_Capacitacion_Activa, 
        v_Id_Capacitacion_Padre, 
        v_Estatus_Curso, 
        v_Conteo_Manual
    FROM `DatosCapacitaciones` `DC` 
    WHERE `DC`.`Id_DatosCap` = _Id_Detalle_Capacitacion;

    -- Validación 3.1: Existencia del recurso
    IF v_Capacitacion_Existe = 0 THEN
        SELECT 'ERROR DE INTEGRIDAD [404]: La capacitación indicada no existe.' AS Mensaje, 'RECURSO_NO_ENCONTRADO' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;
    
    -- Validación 3.2: Recurso no eliminado
    IF v_Capacitacion_Activa = 0 THEN
        SELECT 'ERROR DE LÓGICA [409]: Esta versión del curso está ARCHIVADA o eliminada.' AS Mensaje, 'CONFLICTO_ESTADO' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;
    
    -- Carga de Datos Relacionados (Tabla Padre: Capacitaciones)
    -- Aquí obtenemos el cupo máximo (Meta)
    SELECT `Numero_Capacitacion`, `Asistentes_Programados` 
    INTO v_Folio_Curso, v_Cupo_Maximo 
    FROM `Capacitaciones` 
    WHERE `Id_Capacitacion` = v_Id_Capacitacion_Padre;
    
    -- Validación 3.3: Verificar si el curso ya está cerrado (Estado Final)
    -- Si el curso ya finalizó, no se admiten inscripciones extemporáneas.
    SELECT `Es_Final` INTO v_Es_Estatus_Final 
    FROM `Cat_Estatus_Capacitacion` 
    WHERE `Id_CatEstCap` = v_Estatus_Curso;
    
    IF v_Es_Estatus_Final = 1 THEN
        SELECT CONCAT('ERROR DE LÓGICA [409]: El curso "', v_Folio_Curso, '" ya finalizó o fue cancelado. No admite inscripciones.') AS Mensaje, 'CONFLICTO_ESTADO' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 4: VALIDACIÓN DE UNICIDAD (ANTI-DUPLICADOS)
       Objetivo: Garantizar la Idempotencia. Un usuario no puede ocupar dos filas
       para el mismo curso.
       ═══════════════════════════════════════════════════════════════════════════════════ */
    SELECT COUNT(*) INTO v_Ya_Inscrito 
    FROM `Capacitaciones_Participantes` 
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion 
      AND `Fk_Id_Usuario` = _Id_Usuario_Participante;
    
    IF v_Ya_Inscrito > 0 THEN
        SELECT CONCAT('ERROR DE LÓGICA [409]: El usuario YA está inscrito en "', v_Folio_Curso, '".') AS Mensaje, 'DUPLICADO' AS Accion, NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 5: VALIDACIÓN DE CAPACIDAD (ALGORITMO HÍBRIDO DE CUPO)
       Objetivo: Determinar matemáticamente si existe disponibilidad de asientos.
       
       Lógica: Disponibilidad = Meta - MAX(Conteo_Sistema, Conteo_Manual)
       
       Justificación: 
       Se utiliza MAX() para protección pesimista. Si el sistema dice que hay espacio
       pero el coordinador marcó manualmente que está lleno, el sistema obedece al manual.
       ═══════════════════════════════════════════════════════════════════════════════════ */
    
    -- 5.1 Obtener Conteo del Sistema (Excluyendo status BAJA)
    SELECT COUNT(*) INTO v_Conteo_Sistema
    FROM `Capacitaciones_Participantes`
    WHERE `Fk_Id_DatosCap` = _Id_Detalle_Capacitacion
      AND `Fk_Id_CatEstPart` != c_ESTATUS_BAJA;

    -- 5.2 Aplicar Regla del Máximo (Comparación Sistema vs Manual)
    SET v_Asientos_Ocupados = GREATEST(v_Conteo_Manual, v_Conteo_Sistema);

    -- 5.3 Calcular Delta (Espacios Libres)
    SET v_Cupo_Disponible = v_Cupo_Maximo - v_Asientos_Ocupados;
    
    -- 5.4 Evaluación de Disponibilidad
    IF v_Cupo_Disponible <= 0 THEN
        SELECT 
            CONCAT('ERROR DE NEGOCIO [409]: CUPO LLENO en "', v_Folio_Curso, '". Ocupados: ', v_Asientos_Ocupados, '/', v_Cupo_Maximo) AS Mensaje,
            'CUPO_LLENO' AS Accion,
            NULL AS Id_Registro_Participante;
        LEAVE ProcInsPart;
    END IF;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 6: EJECUCIÓN TRANSACCIONAL (ACID COMMIT)
       Objetivo: Persistir el registro de forma atómica.
       ═══════════════════════════════════════════════════════════════════════════════════ */
    START TRANSACTION;
    
    INSERT INTO `Capacitaciones_Participantes` (
        `Fk_Id_DatosCap`, 
        `Fk_Id_Usuario`, 
        `Fk_Id_CatEstPart`, 
        `Calificacion`, 
        `PorcentajeAsistencia`, 
        `created_at`,               -- Auditoría: Creación
        `updated_at`,               -- Auditoría: Última modificación
        `Fk_Id_Usuario_Created_By`, -- Auditoría: Responsable
        `Fk_Id_Usuario_Updated_By`  -- Auditoría: Responsable
    ) VALUES (
        _Id_Detalle_Capacitacion,
        _Id_Usuario_Participante,
        c_ESTATUS_INSCRITO,  -- Estado Inicial: 1 (Inscrito)
        NULL,                -- Calificación: Pendiente
        NULL,                -- Asistencia: Pendiente
        NOW(),
        NOW(),
        _Id_Usuario_Ejecutor,
        _Id_Usuario_Ejecutor
    );
    
    -- Recuperar el ID autogenerado para retornarlo al cliente
    SET v_Nuevo_Id_Registro = LAST_INSERT_ID();
    
    COMMIT;

    /* ═══════════════════════════════════════════════════════════════════════════════════
       FASE 7: RESPUESTA EXITOSA (UX FEEDBACK)
       Objetivo: Informar al cliente que la operación concluyó correctamente.
       ═══════════════════════════════════════════════════════════════════════════════════ */
    SELECT 
        CONCAT('INSCRIPCIÓN EXITOSA: Usuario inscrito en "', v_Folio_Curso, '". Lugares restantes: ', (v_Cupo_Disponible - 1)) AS Mensaje,
        'INSCRITO' AS Accion,
        v_Nuevo_Id_Registro AS Id_Registro_Participante;

END$$
DELIMITER ;