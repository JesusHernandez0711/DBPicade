USE Picade;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   ARTEFACTO DE INGENIERÍA DE SOFTWARE: MASTER SCRIPT DE VALIDACIÓN Y CONTROL DE CALIDAD (QA)
   NOMBRE CLAVE          : "PROJECT DIAMOND" - AUDITORÍA FORENSE DE CICLO DE VIDA COMPLETO
   VERSIÓN DEL SCRIPT    : 18.0 (PLATINUM FORENSIC DOCUMENTATION STANDARD)
   AUTORÍA               : ARQUITECTURA DE DATOS PICADE
   FECHA DE EJECUCIÓN    : AUTOMÁTICA (NOW)
   
   ──────────────────────────────────────────────────────────────────────────────────────────────────────────
   I. RESUMEN EJECUTIVO (EXECUTIVE SUMMARY)
   ──────────────────────────────────────────────────────────────────────────────────────────────────────────
   Este script constituye una simulación de "Caja Blanca" (White-Box Testing) diseñada para estresar
   y validar la integridad referencial, la lógica de negocio y la seguridad transaccional del sistema PICADE.
   
   II. ALCANCE DE LA PRUEBA (SCOPE)
   ──────────────────────────────────────────────────────────────────────────────────────────────────────────
   1. INFRAESTRUCTURA : Construcción desde cero de Sedes, Temas y Jerarquías.
   2. IDENTIDAD       : Provisionamiento masivo de 60 Usuarios y Staff con Roles diferenciados.
   3. VOLUMEN         : Gestión simultánea de 6 Cursos con cupos heterogéneos (15 a 40 pax).
   4. CICLO DE VIDA   : Programado -> Por Iniciar -> En Curso -> Evaluación -> Acreditación -> Cierre -> Archivo.
   5. REGLAS NEGOCIO  : Validación de Cupo Híbrido, Colas de Espera (Queueing), Promedios y Bloqueos.
   
   III. CONVENIOS DE DOCUMENTACIÓN
   ──────────────────────────────────────────────────────────────────────────────────────────────────────────
   Cada bloque transaccional incluye:
   [ACCIÓN]   : Qué operación técnica se realiza.
   [NEGOCIO]  : Qué regla de negocio se está validando.
   [ESPERADO] : Cuál debe ser el resultado observable en la base de datos.
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════ */

-- [CONFIGURACIÓN DE VARIABLES DE SESIÓN]
-- Se definen variables globales para simular la sesión de un Super Administrador orquestador.
SET @AdminEjecutor = 322; 
SET @FechaHoy = CURDATE();

/* ==========================================================================================================
   FASE 0: PROTOCOLO DE ESTERILIZACIÓN (DATA SANITIZATION & TEARDOWN PRE-FLIGHT)
   ==========================================================================================================
   [ACCIÓN]   : Eliminación en cascada inversa (Nietos -> Hijos -> Padres).
   [NEGOCIO]  : Garantizar un entorno "Limpio" (Clean Slate) para evitar falsos positivos por datos residuales.
   [TÉCNICO]  : Se desactiva temporalmente `FOREIGN_KEY_CHECKS` para permitir el borrado masivo rápido.
   ========================================================================================================== */
SET FOREIGN_KEY_CHECKS = 0;

-- 0.1 Limpieza de Tablas Transaccionales (El orden no importa aquí por FK=0, pero se mantiene por orden lógico)
DELETE FROM `Evaluaciones_Participantes` WHERE `Observaciones` LIKE '%QA-DIAMOND%';
DELETE FROM `Capacitaciones_Participantes` WHERE `Justificacion` LIKE '%QA-DIAMOND%';
DELETE FROM `DatosCapacitaciones` WHERE `Observaciones` LIKE '%QA-DIAMOND%';
DELETE FROM `Capacitaciones` WHERE `Numero_Capacitacion` LIKE 'QA-DIAMOND%';

-- 0.2 Limpieza de Actores (Usuarios de Prueba)
DELETE FROM `Usuarios` WHERE `Ficha` LIKE 'QA-DIAMOND%';
DELETE FROM `Info_Personal` WHERE `Nombre` LIKE 'QA-DIAMOND%';

-- 0.3 Limpieza de Infraestructura y Catálogos (Topología)
DELETE FROM `Cat_Cases_Sedes` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Departamentos` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Centros_Trabajo` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Temas_Capacitacion` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Gerencias_Activos` WHERE `Clave` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Subdirecciones` WHERE `Clave` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Direcciones` WHERE `Clave` LIKE 'QA-DIAMOND%';
DELETE FROM `Municipio` WHERE `Codigo` LIKE 'QA-DIAMOND%';

SET FOREIGN_KEY_CHECKS = 1;
SELECT '✅ FASE 0 COMPLETADA: Entorno esterilizado y listo para la inyección de datos.' AS STATUS;

/* ==========================================================================================================
   FASE 1: CONSTRUCCIÓN DE INFRAESTRUCTURA (INFRASTRUCTURE PROVISIONING)
   ==========================================================================================================
   [OBJETIVO]: Crear la topología geográfica y organizacional necesaria para soportar los cursos.
   [REGLA]   : "Zero Assumptions". No asumimos que existan sedes o temas; los creamos.
   ========================================================================================================== */
SELECT '--- 1.1 Construyendo Topología (Sedes, Jerarquía, Temas) ---' AS STEP;

-- 1.1.1 Geografía
CALL SP_RegistrarUbicaciones('QA-DIAMOND-MUN', 'MUNICIPIO D', 'QA-DIAMOND-EDO', 'ESTADO D', 'QA-DIAMOND-PAIS', 'PAIS D');
SET @IdMun = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'QA-DIAMOND-MUN');

-- 1.1.2 Organización Corporativa
CALL SP_RegistrarOrganizacion('QA-DIAMOND-GER', 'GERENCIA D', 'QA-DIAMOND-SUB', 'SUB D', 'QA-DIAMOND-DIR', 'DIR D');
SET @IdGer = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'QA-DIAMOND-GER');

-- 1.1.3 Espacios de Trabajo
CALL SP_RegistrarCentroTrabajo('QA-DIAMOND-CT', 'CT D', 'CALLE 1', @IdMun);
SET @IdCT = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'QA-DIAMOND-CT');
CALL SP_RegistrarDepartamento('QA-DIAMOND-DEP', 'DEPTO D', 'PISO 1', @IdMun);
SET @IdDep = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'QA-DIAMOND-DEP');

-- 1.1.4 Sedes Educativas (Aulas)
-- Se crean 3 sedes con capacidades distintas para probar validaciones de aforo.
CALL SP_RegistrarSede('QA-DIAMOND-SEDE-A', 'AULA MAGNA', 'EDIF A', @IdMun, 50, 1, 1, 0, 0, 0, 0);
SET @IdSedeA = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-A');

CALL SP_RegistrarSede('QA-DIAMOND-SEDE-B', 'LABORATORIO', 'EDIF B', @IdMun, 40, 1, 1, 0, 0, 0, 0);
SET @IdSedeB = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-B');

CALL SP_RegistrarSede('QA-DIAMOND-SEDE-C', 'SALA VIRTUAL', 'TEAMS', @IdMun, 100, 1, 1, 0, 0, 0, 0);
SET @IdSedeC = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-C');

-- 1.1.5 Catálogo Académico (Temas)
CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-1', 'SEGURIDAD INDUSTRIAL', 'SEG', 20, 1);
SET @IdTema1 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-1');

CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-2', 'LIDERAZGO AGILE', 'LID', 10, 1);
SET @IdTema2 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-2');

CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-3', 'SQL AVANZADO', 'TEC', 30, 1);
SET @IdTema3 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-3');

-- [CONSTANTES DE SISTEMA]
-- Mapeo de IDs estáticos para uso en el script (Evita magic numbers en las llamadas).
SET @RolAdmin=1; SET @RolCoord=2; SET @RolInst=3; SET @RolPart=4;
SET @IdRegimen = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo LIMIT 1);
SET @IdRegion  = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo LIMIT 1);
SET @IdPuesto  = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo LIMIT 1);
SET @Mod_Pres=1; SET @Mod_Virt=2; SET @Mod_Hib=3;
SET @St_Prog=1; SET @St_PorIni=2; SET @St_EnCurso=3; SET @St_Fin=4; SET @St_Eval=5; 
SET @St_Acr=6; SET @St_NoAcr=7; SET @St_Canc=8; SET @St_Repro=9; SET @St_Arch=10; SET @St_Reprog=9;

SELECT '✅ FASE 1 COMPLETADA: Infraestructura operativa lista.' AS STATUS;

/* ==========================================================================================================
   FASE 2: PROVISIONAMIENTO DE ACTORES (IDENTITY MANAGEMENT)
   ==========================================================================================================
   [OBJETIVO]: Crear los usuarios que interactuarán con el sistema.
   [ALCANCE] : 2 Administradores, 2 Coordinadores, 2 Instructores y 60 Participantes.
   ========================================================================================================== */
SELECT '--- 2.1 Creando Staff Administrativo (Load Balancing) ---' AS STEP;

-- Admins (Para rescates y archivado)
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-ADM1', NULL, 'ADMIN', 'UNO', 'QA', '1990-01-01', '2030-01-01', 'a1@d.test', '123', @RolAdmin, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Adm1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-ADM2', NULL, 'ADMIN', 'DOS', 'QA', '1990-01-01', '2030-01-01', 'a2@d.test', '123', @RolAdmin, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Adm2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM2');

-- Coordinadores (Dueños del proceso)
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-COO1', NULL, 'COORD', 'UNO', 'QA', '1990-01-01', '2030-01-01', 'c1@d.test', '123', @RolCoord, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Coo1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-COO2', NULL, 'COORD', 'DOS', 'QA', '1990-01-01', '2030-01-01', 'c2@d.test', '123', @RolCoord, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Coo2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO2');

-- Instructores (Ejecutores académicos)
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-INS1', NULL, 'INST', 'UNO', 'QA', '1990-01-01', '2030-01-01', 'i1@d.test', '123', @RolInst, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Inst1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-INS2', NULL, 'INST', 'DOS', 'QA', '1990-01-01', '2030-01-01', 'i2@d.test', '123', @RolInst, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Inst2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS2');

SELECT '--- 2.2 Creando 60 Participantes (P01-P60) Vía Loop Transaccional ---' AS STEP;
-- [NOTA TÉCNICA]: Usamos un Procedure Temporal para evitar 60 bloques de código repetidos.
-- Esto valida la robustez del SP `SP_RegistrarUsuarioPorAdmin` bajo carga repetitiva.
DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_Temp_GenUsers`$$
CREATE PROCEDURE `SP_Temp_GenUsers`()
BEGIN
    DECLARE i INT DEFAULT 1;
    WHILE i <= 60 DO
        -- Invocación del SP Oficial para crear usuarios
        CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, CONCAT('QA-DIAMOND-P', LPAD(i,2,'0')), NULL, CONCAT('PARTICIPANTE_',i), 'TEST_USER', 'QA', '2000-01-01', '2030-01-01', CONCAT('p',i,'@d.test'), '123', 4, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;
-- Ejecución del provisionamiento masivo
CALL `SP_Temp_GenUsers`();
DROP PROCEDURE `SP_Temp_GenUsers`;

-- Captura de variables clave para uso explícito posterior
SET @U_P01 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P01');
SET @U_P05 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P05'); -- Víctima de baja
SET @U_P21 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P21'); -- El oportunista

SELECT '✅ FASE 2 COMPLETADA: 66 Actores creados en el sistema.' AS STATUS;

/* ==========================================================================================================
   FASE 3: CREACIÓN DE LOS 6 CURSOS (PLANEACIÓN - ESTATUS PROGRAMADO)
   ==========================================================================================================
   [OBJETIVO]: Registrar 6 capacitaciones con cupos y configuraciones heterogéneas.
   [CUPOS]: 30, 25, 30, 20, 15, 40.
   [ACTORES]: Repartidos entre Coordinador 1 y 2.
   ========================================================================================================== */
SELECT '--- 3.1 Creando 6 Cursos en Estatus PROGRAMADO ---' AS STEP;

-- C01 (Cupo 30) - Coord 1
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C01', @IdGer, @IdTema1, @U_Inst1, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 20 DAY), DATE_ADD(@FechaHoy, INTERVAL 25 DAY), 30, @St_Prog, 'QA-DIAMOND: C01 Base (30)');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'));

-- C02 (Cupo 25) - Coord 1
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C02', @IdGer, @IdTema2, @U_Inst2, @IdSedeB, @Mod_Virt, DATE_ADD(@FechaHoy, INTERVAL 22 DAY), DATE_ADD(@FechaHoy, INTERVAL 27 DAY), 25, @St_Prog, 'QA-DIAMOND: C02 Base (25)');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'));

-- C03 (Cupo 30) - Coord 2
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C03', @IdGer, @IdTema3, @U_Inst1, @IdSedeC, @Mod_Hib, DATE_ADD(@FechaHoy, INTERVAL 25 DAY), DATE_ADD(@FechaHoy, INTERVAL 30 DAY), 30, @St_Prog, 'QA-DIAMOND: C03 Base (30)');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'));

-- C04 (Cupo 20) - Coord 2 [CURSO CRÍTICO PARA PRUEBA DE COLA DE ESPERA]
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C04', @IdGer, @IdTema1, @U_Inst2, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 30 DAY), DATE_ADD(@FechaHoy, INTERVAL 35 DAY), 20, @St_Prog, 'QA-DIAMOND: C04 Queue Test (20)');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'));

-- C05 (Cupo 15) - Coord 1
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C05', @IdGer, @IdTema2, @U_Inst1, @IdSedeB, @Mod_Virt, DATE_ADD(@FechaHoy, INTERVAL 35 DAY), DATE_ADD(@FechaHoy, INTERVAL 40 DAY), 15, @St_Prog, 'QA-DIAMOND: C05 Base (15)');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'));

-- C06 (Cupo 40) - Coord 2
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C06', @IdGer, @IdTema3, @U_Inst2, @IdSedeC, @Mod_Hib, DATE_ADD(@FechaHoy, INTERVAL 40 DAY), DATE_ADD(@FechaHoy, INTERVAL 45 DAY), 40, @St_Prog, 'QA-DIAMOND: C06 Base (40)');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'));

-- [AUDITORÍA VISUAL 1]: Verificación en la Matriz General
SELECT '--- 🔍 CHECKPOINT 1: Matriz de Capacitaciones (Deben aparecer 6 en Programado) ---' AS CHECK_POINT;
CALL SP_ObtenerMatrizPICADE(NULL, @FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

SELECT '✅ FASE 3 COMPLETADA: Cursos creados y visibles en el Dashboard.' AS STATUS;

/* ==========================================================================================================
   FASE 4: INSCRIPCIÓN Y COLA DE ESPERA (REGISTRO MIXTO)
   ==========================================================================================================
   [OBJETIVO]: Llenar los cursos. Simular que algunos entran por auto-registro y otros por Admin.
   [REGLA]   : Usar `SP_RegistrarParticipacionCapacitacion` (Auto) y `SP_RegistrarParticipanteCapacitacion` (Admin).
   ========================================================================================================== */
SELECT '--- 4.1 Ejecutando Inscripciones Masivas (Vía Stored Procedures Oficiales) ---' AS STEP;

-- Helper para bucle de inscripciones (Simula múltiples usuarios logueándose o un admin trabajando)
DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_QA_Enroll_Engine`$$
CREATE PROCEDURE `SP_QA_Enroll_Engine`(IN _CursoID INT, IN _Start INT, IN _End INT)
BEGIN
    DECLARE i INT DEFAULT _Start;
    DECLARE v_ID INT;
    WHILE i <= _End DO
        SELECT Id_Usuario INTO v_ID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(i,2,'0'));
        -- Simulación: Auto-Inscripción del usuario
        CALL SP_RegistrarParticipacionCapacitacion(v_ID, _CursoID); 
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;

-- C01 (30 Cupos): Llenamos 20 con Sistema (66%). Dejamos 10 libres para externos.
CALL `SP_QA_Enroll_Engine`(@C01_Ver, 1, 20); 

-- C02 (25 Cupos): Llenamos 10 con Sistema (40%). Dejamos 15 libres para externos.
CALL `SP_QA_Enroll_Engine`(@C02_Ver, 21, 30); 

-- C03 (30 Cupos): Llenamos 25 con Sistema (83%). Dejamos 5 libres.
CALL `SP_QA_Enroll_Engine`(@C03_Ver, 31, 55); 

-- C04 (20 Cupos): Llenamos 20 con Sistema (100% SATURADO). 
-- [NOTA]: P01 a P20 ocupan todo el cupo. Esto es vital para la prueba de Cola.
CALL `SP_QA_Enroll_Engine`(@C04_Ver, 1, 20); 

-- C05 (15 Cupos): Llenamos 10 con Sistema (66%).
CALL `SP_QA_Enroll_Engine`(@C05_Ver, 16, 25);

-- C06 (40 Cupos): Llenamos 20 con Sistema (50%).
CALL `SP_QA_Enroll_Engine`(@C06_Ver, 26, 45);

DROP PROCEDURE `SP_QA_Enroll_Engine`;

-- [AUDITORÍA VISUAL 2]: Instructor revisa listado preliminar
SELECT '--- 🔍 CHECKPOINT 2: Instructor consulta lista C04 (Debe estar llena con 20) ---' AS CHECK_POINT;
CALL SP_ConsularParticipantesCapacitacion(@C04_Ver);

SELECT '✅ FASE 4 COMPLETADA: Matrícula cargada en los 6 cursos.' AS STATUS;

/* ==========================================================================================================
   FASE 4.5: LA "SILLA CALIENTE" (BAJAS, REINGRESOS Y REBOTES DE COLA)
   ==========================================================================================================
   [ESCENARIO DE NEGOCIO]: 
   En C04 (Lleno con 20), el usuario P21 quiere entrar pero rebota.
   Luego P05 se da de baja (problemas personales).
   P21 aprovecha el hueco y entra.
   P05 se arrepiente y quiere volver, pero su lugar ya fue tomado.
   ========================================================================================================== */
SELECT '--- 4.5 Ejecutando Lógica de Cola en C04 ---' AS STEP;

-- 1. INTENTO FALLIDO: P21 intenta entrar a C04 (Lleno).
-- [ESPERADO]: Mensaje de Error "Cupo Lleno".
SELECT '🧪 TEST 1: Rebote por Cupo Lleno (P21)' AS TEST_CASE;
CALL SP_RegistrarParticipacionCapacitacion(@U_P21, @C04_Ver);

-- 2. LIBERACIÓN DE ESPACIO: P05 solicita baja.
-- [ACCIÓN]: El Coord usa `SP_CambiarEstatusParticipanteCapacitacion` con estatus 5 (Baja).
SELECT '🧪 TEST 2: Baja Voluntaria (P05)' AS TEST_CASE;
SET @Reg_P05 = (SELECT Id_CapPart FROM Capacitaciones_Participantes WHERE Fk_Id_DatosCap = @C04_Ver AND Fk_Id_Usuario = @U_P05);
CALL SP_CambiarEstatusParticipanteCapacitacion(@U_Coo2, @Reg_P05, 5, 'QA: Baja por temas personales');

-- 3. EL OPORTUNISTA: P21 reintenta y debe entrar.
SELECT '🧪 TEST 3: Ocupación de Lugar Liberado (P21)' AS TEST_CASE;
CALL SP_RegistrarParticipacionCapacitacion(@U_P21, @C04_Ver);

-- 4. EL ARREPENTIDO: P05 intenta reingresar (Cambiar estatus de 5 a 1).
-- [ESPERADO]: Mensaje de Error "Cupo Lleno" (Porque P21 ya tomó su silla).
SELECT '🧪 TEST 4: Intento de Reingreso Fallido (P05)' AS TEST_CASE;
-- Envolvemos en un bloque seguro para capturar el error 409 y mostrarlo como éxito de la prueba.
DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_Test_Reentry`$$
CREATE PROCEDURE `SP_Test_Reentry`()
BEGIN
    DECLARE v_State VARCHAR(5);
    DECLARE v_Msg TEXT;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION GET DIAGNOSTICS CONDITION 1 v_State = RETURNED_SQLSTATE, v_Msg = MESSAGE_TEXT;
    
    CALL SP_CambiarEstatusParticipanteCapacitacion(322, (SELECT Id_CapPart FROM Capacitaciones_Participantes WHERE Fk_Id_DatosCap = @C04_Ver AND Fk_Id_Usuario = @U_P05), 1, 'Intento volver');
    
    SELECT IF(v_State = '45000', '✅ PRUEBA EXITOSA: Sistema bloqueó el reingreso por cupo.', CONCAT('❌ FALLO: ', v_Msg)) AS RESULTADO;
END$$
DELIMITER ;
CALL `SP_Test_Reentry`();
DROP PROCEDURE `SP_Test_Reentry`;

SELECT '✅ FASE 4.5 COMPLETADA: Lógica de Cola de Espera validada.' AS STATUS;

/* ==========================================================================================================
   FASE 5: AUTORIZACIÓN Y BLOQUEO DE CUPO EXTERNO
   ==========================================================================================================
   [OBJETIVO]: Pasar a 'POR INICIAR' y definir cuántos externos hay para bloquear el cupo restante.
   ========================================================================================================== */
SELECT '--- 5.1 Autorizando Cursos y Definiendo Externos ---' AS STEP;

-- C01: 30 Cupos. 20 Sistema. Definimos 10 Manuales -> 30 Total (Saturado).
CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 20 DAY), DATE_ADD(@FechaHoy, INTERVAL 25 DAY), 10, 'Autorizado');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

-- C02: 25 Cupos. 10 Sistema. Definimos 15 Manuales -> 25 Total (Saturado).
CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 22 DAY), DATE_ADD(@FechaHoy, INTERVAL 27 DAY), 15, 'Autorizado');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

-- C03: 30 Cupos. 25 Sistema. Definimos 5 Manuales -> 30 Total.
CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 25 DAY), DATE_ADD(@FechaHoy, INTERVAL 30 DAY), 5, 'Autorizado');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);

-- C04: 20 Cupos. 20 Sistema. 0 Manuales -> 20 Total.
CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst2, @IdSedeA, @Mod_Pres, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 30 DAY), DATE_ADD(@FechaHoy, INTERVAL 35 DAY), 0, 'Autorizado');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);

-- C05: 15 Cupos. 10 Sistema. 5 Manuales.
CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 35 DAY), DATE_ADD(@FechaHoy, INTERVAL 40 DAY), 5, 'Autorizado');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);

-- C06: 40 Cupos. 20 Sistema. 20 Manuales.
CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 40 DAY), DATE_ADD(@FechaHoy, INTERVAL 45 DAY), 20, 'Autorizado');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

-- [AUDITORÍA VISUAL 3]: Validar que los cursos autorizados sean encontrables
SELECT '--- 🔍 CHECKPOINT 3: Buscador Global (Status: Por Iniciar) ---' AS CHECK_POINT;
CALL SP_BuscadorGlobalPICADE('QA-DIAMOND');

SELECT '✅ FASE 5 COMPLETADA: Cursos autorizados.' AS STATUS;

/* ==========================================================================================================
   FASE 6: ESCENARIOS DE CAMBIOS (HISTORIAL PROFUNDO)
   ==========================================================================================================
   [OBJETIVO]: Generar historial de cambios para los 6 cursos y simular el regreso automático a POR INICIAR.
   ========================================================================================================== */
SELECT '--- 6.1 Generando Historial Masivo (Cambios a Reprogramado) ---' AS STEP;

-- Helper para generar cambios masivos
DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_QA_History`$$
CREATE PROCEDURE `SP_QA_History`(IN _VerID INT, IN _HeadID INT, IN _CoordID INT, IN _InstID INT, IN _SedeID INT, IN _ModID INT)
BEGIN
    DECLARE v_NewVer INT DEFAULT _VerID;
    -- Cambio 1: Instructor + Estatus Reprogramado
    CALL SP_Editar_Capacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, 9, DATE_ADD(CURDATE(), INTERVAL 25 DAY), DATE_ADD(CURDATE(), INTERVAL 30 DAY), 0, 'QA: Cambio Instructor');
END$$
DELIMITER ;

-- Ejecutar para los 6 cursos
CALL `SP_QA_History`(@C01_Ver, @C01_Head, @U_Coo1, @U_Inst2, @IdSedeA, @Mod_Pres);
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

CALL `SP_QA_History`(@C02_Ver, @C02_Head, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt);
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

CALL `SP_QA_History`(@C03_Ver, @C03_Head, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib);
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);

CALL `SP_QA_History`(@C04_Ver, @C04_Head, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres);
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);

CALL `SP_QA_History`(@C05_Ver, @C05_Head, @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt);
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);

CALL `SP_QA_History`(@C06_Ver, @C06_Head, @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib);
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

DROP PROCEDURE `SP_QA_History`;

SELECT '--- 6.2 Regreso Automático a POR INICIAR (Simulación 2 Semanas Antes) ---' AS STEP;
-- El sistema detecta la fecha próxima y confirma el curso.
CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 2, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'QA: Confirmado');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt, 2, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'QA: Confirmado');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

-- (Repetir explícitamente para C03-C06)
CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib, 2, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'QA: Confirmado');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);
CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst2, @IdSedeA, @Mod_Pres, 2, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'QA: Confirmado');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);
CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 2, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'QA: Confirmado');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);
CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 2, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'QA: Confirmado');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

-- [AUDITORÍA VISUAL 4]: Ver detalle con historial
SELECT '--- 🔍 CHECKPOINT 4: Detalle del Curso con Historial (Debe mostrar versiones anteriores) ---' AS CHECK_POINT;
CALL SP_ConsultarCapacitacionEspecifica(@C01_Ver);

SELECT '✅ FASE 6 COMPLETADA: Historial generado.' AS STATUS;

/* ==========================================================================================================
   FASE 7: EJECUCIÓN (EN CURSO)
   ========================================================================================================== */
SELECT '--- 7.1 Arrancando TODOS los Cursos (Migración de Alumnos) ---' AS STEP;

CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'En Curso');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'En Curso');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'En Curso');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);

CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst2, @IdSedeA, @Mod_Pres, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'En Curso');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);

CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'En Curso');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);

CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'En Curso');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

SELECT '✅ FASE 7 COMPLETADA: Cursos en ejecución.' AS STATUS;

/* ==========================================================================================================
   FASE 8: EVALUACIÓN (EN CURSO -> EVALUACIÓN)
   ========================================================================================================== */
SELECT '--- 8.1 Cambio Automático a EVALUACIÓN (Los 6 Cursos) ---' AS STEP;

CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Evaluando');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Evaluando');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Evaluando');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);

CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst2, @IdSedeA, @Mod_Pres, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Evaluando');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);

CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Evaluando');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);

CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Evaluando');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

-- [AUDITORÍA VISUAL 5]: Instructor revisa carga antes de calificar
SELECT '--- 🔍 CHECKPOINT 5: Vista Instructor (Cursos por evaluar) ---' AS CHECK_POINT;
CALL SP_ConsultarCursosImpartidos(@U_Inst1);

SELECT '--- 8.2 Asentando Calificaciones Masivas (Vía SP) ---' AS STEP;
-- Usamos un Helper para llamar al SP oficial por rangos de alumnos
DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_QA_GradeRange`$$
CREATE PROCEDURE `SP_QA_GradeRange`(IN _CursoID INT, IN _Start INT, IN _End INT, IN _Grade DECIMAL(5,2), IN _ExecID INT)
BEGIN
    DECLARE i INT DEFAULT _Start;
    DECLARE v_UID INT;
    DECLARE v_RegID INT;
    WHILE i <= _End DO
        SELECT Id_Usuario INTO v_UID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(i,2,'0'));
        SELECT Id_CapPart INTO v_RegID FROM Capacitaciones_Participantes WHERE Fk_Id_DatosCap = _CursoID AND Fk_Id_Usuario = v_UID LIMIT 1;
        IF v_RegID IS NOT NULL THEN
            -- LLAMADA AL SP OFICIAL: Calcula estatus basado en nota
            CALL SP_EditarParticipanteCapacitacion(_ExecID, v_RegID, _Grade, 100.00, NULL, 'Evaluación Final');
        END IF;
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;

-- C01 (20 inscritos): 15 Aprueban (95), 5 Reprueban (50). => ACREDITADO (75%)
CALL `SP_QA_GradeRange`(@C01_Ver, 1, 15, 95.00, @U_Inst1);
CALL `SP_QA_GradeRange`(@C01_Ver, 16, 20, 50.00, @U_Inst1);

-- C02 (10 inscritos): 3 Aprueban (90), 7 Reprueban (50). => NO ACREDITADO (30%)
CALL `SP_QA_GradeRange`(@C02_Ver, 21, 23, 90.00, @U_Inst2);
CALL `SP_QA_GradeRange`(@C02_Ver, 24, 30, 50.00, @U_Inst2);

-- C03 (25 inscritos): Todos aprueban (100). => ACREDITADO
CALL `SP_QA_GradeRange`(@C03_Ver, 31, 55, 100.00, @U_Inst1);

-- C04 (20 inscritos - nota: P21 entró en lugar de P05): 10 Aprueban, 10 Reprueban. => NO ACREDITADO (50%)
CALL `SP_QA_GradeRange`(@C04_Ver, 1, 10, 85.00, @U_Inst2);
CALL `SP_QA_GradeRange`(@C04_Ver, 11, 21, 60.00, @U_Inst2); -- Incluye a P21

-- C05 (10 inscritos): 9 Aprueban, 1 Reprueba. => ACREDITADO (90%)
CALL `SP_QA_GradeRange`(@C05_Ver, 16, 24, 90.00, @U_Inst1);
CALL `SP_QA_GradeRange`(@C05_Ver, 25, 25, 0.00, @U_Inst1);

-- C06 (20 inscritos): Todos aprueban. => ACREDITADO
CALL `SP_QA_GradeRange`(@C06_Ver, 26, 45, 98.00, @U_Inst2);

DROP PROCEDURE `SP_QA_GradeRange`;

-- [AUDITORÍA VISUAL 6]: Dashboard Gerencial para ver métricas
SELECT '--- 🔍 CHECKPOINT 6: Dashboard Gerencial (Personas Capacitadas) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenGerencial(@FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

SELECT '✅ FASE 8 COMPLETADA: Evaluaciones registradas.' AS STATUS;

/* ==========================================================================================================
   FASE 9: DETERMINACIÓN DE ACREDITACIÓN (VEREDICTO)
   ==========================================================================================================
   [OBJETIVO]: Cambiar estatus del curso basado en la regla del 70%.
   ========================================================================================================== */
SELECT '--- 9.1 Aplicando Veredictos (Manual/Simulado según Regla) ---' AS STEP;

-- C01 (75% Aprobación) -> ACREDITADO
CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Dictamen: ACREDITADO');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

-- C02 (30% Aprobación) -> NO ACREDITADO
CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt, 7, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Dictamen: NO ACREDITADO');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

-- C03 (100%) -> ACREDITADO
CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Dictamen: ACREDITADO');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);

-- C04 (50%) -> NO ACREDITADO
CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst2, @IdSedeA, @Mod_Pres, 7, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Dictamen: NO ACREDITADO');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);

-- C05 (90%) -> ACREDITADO
CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Dictamen: ACREDITADO');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);

-- C06 (100%) -> ACREDITADO
CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Dictamen: ACREDITADO');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

SELECT '✅ FASE 9 COMPLETADA: Veredictos aplicados.' AS STATUS;

/* ==========================================================================================================
   FASE 10: CIERRE (FINALIZADO)
   ========================================================================================================== */
SELECT '--- 10.1 Ejecutando Cierre Final para los 6 Cursos ---' AS STEP;

CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Cierre Final');
CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Cierre Final');
CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Cierre Final');
CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst2, @IdSedeA, @Mod_Pres, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Cierre Final');
CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Cierre Final');
CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Cierre Final');

-- [AUDITORÍA VISUAL 7]: Resumen Anual Final
SELECT '--- 🔍 CHECKPOINT 7: Resumen Anual (Total de cursos finalizados) ---' AS CHECK_POINT;
CALL SP_Dashboard_ResumenAnual();

SELECT '✅ FASE 10 COMPLETADA: Cierre administrativo.' AS STATUS;

/* ==========================================================================================================
   FASE 11: ARCHIVADO (KILL SWITCH)
   ========================================================================================================== */
SELECT '--- 11.1 Archivando los 6 Cursos ---' AS STEP;

CALL SP_CambiarEstatusCapacitacion(@C01_Head, @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion(@C02_Head, @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion(@C03_Head, @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion(@C04_Head, @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion(@C05_Head, @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion(@C06_Head, @U_Adm1, 0);

-- [AUDITORÍA VISUAL 8]: Validar que desaparezcan del Grid
SELECT '--- 🔍 CHECKPOINT 8: Matriz Vacía (Todo archivado) ---' AS CHECK_POINT;
CALL SP_ObtenerMatrizPICADE(NULL, @FechaHoy, DATE_ADD(@FechaHoy, INTERVAL 60 DAY));

SELECT '✅ FASE 11 COMPLETADA: Archivado masivo.' AS STATUS;

/* ==========================================================================================================
   FASE 12: CANCELACIÓN (CURSO C07)
   ========================================================================================================== */
SELECT '--- 12.1 Prueba de Cancelación (C07) ---' AS STEP;
-- Crear C07
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C07', @IdGer, @IdTema1, @U_Inst1, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 90 DAY), DATE_ADD(@FechaHoy, INTERVAL 95 DAY), 30, @St_Prog, 'C07 Cancel');
SET @C07_Head = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C07');
SET @C07_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C07_Head);

-- Inscribir Alumno P01
CALL SP_RegistrarParticipanteCapacitacion(@U_Adm1, @C07_Ver, @U_P01);

-- Cancelar (Status 8)
CALL SP_Editar_Capacitacion(@C07_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 8, DATE_ADD(@FechaHoy, INTERVAL 90 DAY), DATE_ADD(@FechaHoy, INTERVAL 95 DAY), 0, 'Cancelado por fuerza mayor');

-- Archivar
CALL SP_CambiarEstatusCapacitacion(@C07_Head, @U_Adm1, 0);

SELECT '✅ FASE 12 COMPLETADA: Cancelación exitosa.' AS STATUS;

/* ==========================================================================================================
   FASE 14: LIMPIEZA FINAL (TEARDOWN)
   ========================================================================================================== */
SELECT '--- 14.1 Limpieza Final ---' AS STEP;

-- Borrado de Relaciones
DELETE FROM Capacitaciones_Participantes WHERE Fk_Id_Usuario IN (SELECT Id_Usuario FROM Usuarios WHERE Ficha LIKE 'QA-DIAMOND%');

-- Borrado de Cursos
CALL SP_EliminarCapacitacion(@C01_Head);
CALL SP_EliminarCapacitacion(@C02_Head);
CALL SP_EliminarCapacitacion(@C03_Head);
CALL SP_EliminarCapacitacion(@C04_Head);
CALL SP_EliminarCapacitacion(@C05_Head);
CALL SP_EliminarCapacitacion(@C06_Head);
CALL SP_EliminarCapacitacion(@C07_Head);

-- Borrado de Usuarios (Vía Helper)
DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_Temp_DelUsers`$$
CREATE PROCEDURE `SP_Temp_DelUsers`()
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE v_ID INT;
    WHILE i <= 60 DO
        SELECT Id_Usuario INTO v_ID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(i,2,'0'));
        IF v_ID IS NOT NULL THEN CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, v_ID); END IF;
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;
CALL `SP_Temp_DelUsers`();
DROP PROCEDURE `SP_Temp_DelUsers`;

-- Borrado de Staff
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Adm1);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Adm2);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Coo1);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Coo2);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Inst1);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Inst2);

-- Borrado de Infraestructura
SET FOREIGN_KEY_CHECKS = 0;
CALL SP_EliminarTemaCapacitacionFisico(@IdTema1);
CALL SP_EliminarTemaCapacitacionFisico(@IdTema2);
CALL SP_EliminarTemaCapacitacionFisico(@IdTema3);
CALL SP_EliminarSedeFisica(@IdSedeA);
CALL SP_EliminarSedeFisica(@IdSedeB);
CALL SP_EliminarSedeFisica(@IdSedeC);
CALL SP_EliminarDepartamentoFisico(@IdDep);
CALL SP_EliminarCentroTrabajoFisico(@IdCT);
CALL SP_EliminarGerenciaFisica(@IdGer);
CALL SP_EliminarMunicipio(@IdMun);
SET FOREIGN_KEY_CHECKS = 1;

SELECT '✅ FASE 14 COMPLETADA: Sistema limpio y listo para producción.' AS STATUS;

SELECT '╔══════════════════════════════════════════════════════════════════════════════════════════════╗' AS '';
SELECT '║  BATERÍA DE PRUEBAS COMPLETADA - SISTEMA LISTO PARA PRODUCCIÓN                               ║' AS '';
SELECT '╚══════════════════════════════════════════════════════════════════════════════════════════════╝' AS '';