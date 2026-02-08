USE Picade;

/* ══════════════════════════════════════════════════════════════════════════════════════════════════════════
   ARTEFACTO : MASTER SCRIPT QA "PROJECT DIAMOND" (V19.0 - FINAL CORRECTED)
   OBJETIVO  : Validación de Ciclo de Vida Completo (6 Cursos), Caos Masivo e Historial Profundo.
   ESTÁNDAR  : PLATINUM FORENSIC - DOCUMENTACIÓN TÉCNICA DETALLADA.
   ══════════════════════════════════════════════════════════════════════════════════════════════════════════ */

-- [CONFIGURACIÓN DE SESIÓN]
SET @AdminEjecutor = 322; 
SET @FechaHoy = CURDATE();

-- ==========================================================================================================
-- FASE 0: PROTOCOLO DE ESTERILIZACIÓN (DATA SANITIZATION)
-- ==========================================================================================================
-- [ACCIÓN]: Borrado seguro de tablas en orden de dependencia inversa.
SET FOREIGN_KEY_CHECKS = 0;
DELETE FROM `Evaluaciones_Participantes` WHERE `Observaciones` LIKE '%QA-DIAMOND%';
DELETE FROM `Capacitaciones_Participantes` WHERE `Justificacion` LIKE '%QA-DIAMOND%';
DELETE FROM `DatosCapacitaciones` WHERE `Observaciones` LIKE '%QA-DIAMOND%';
DELETE FROM `Capacitaciones` WHERE `Numero_Capacitacion` LIKE 'QA-DIAMOND%';
DELETE FROM `Usuarios` WHERE `Ficha` LIKE 'QA-DIAMOND%';
DELETE FROM `Info_Personal` WHERE `Nombre` LIKE 'QA-DIAMOND%';
-- Catálogos
DELETE FROM `Cat_Cases_Sedes` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Departamentos` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Centros_Trabajo` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Temas_Capacitacion` WHERE `Codigo` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Gerencias_Activos` WHERE `Clave` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Subdirecciones` WHERE `Clave` LIKE 'QA-DIAMOND%';
DELETE FROM `Cat_Direcciones` WHERE `Clave` LIKE 'QA-DIAMOND%';
DELETE FROM `Municipio` WHERE `Codigo` LIKE 'QA-DIAMOND%';
SET FOREIGN_KEY_CHECKS = 1;

SELECT '✅ FASE 0: Entorno limpio y listo.' AS STATUS;

/* ==========================================================================================================
   FASE 1: INFRAESTRUCTURA (TOPOLOGÍA)
   ========================================================================================================== */
SELECT '--- 1.1 Construyendo Topología ---' AS STEP;
CALL SP_RegistrarUbicaciones('QA-DIAMOND-MUN', 'MUNICIPIO D', 'QA-DIAMOND-EDO', 'ESTADO D', 'QA-DIAMOND-PAIS', 'PAIS D');
SET @IdMun = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'QA-DIAMOND-MUN');
CALL SP_RegistrarOrganizacion('QA-DIAMOND-GER', 'GERENCIA D', 'QA-DIAMOND-SUB', 'SUB D', 'QA-DIAMOND-DIR', 'DIR D');
SET @IdGer = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'QA-DIAMOND-GER');
CALL SP_RegistrarCentroTrabajo('QA-DIAMOND-CT', 'CT D', 'CALLE 1', @IdMun);
SET @IdCT = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'QA-DIAMOND-CT');
CALL SP_RegistrarDepartamento('QA-DIAMOND-DEP', 'DEPTO D', 'PISO 1', @IdMun);
SET @IdDep = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'QA-DIAMOND-DEP');

-- Sedes
CALL SP_RegistrarSede('QA-DIAMOND-SEDE-A', 'AULA A', 'EDIF A', @IdMun, 50, 1, 1, 0, 0, 0, 0);
SET @IdSedeA = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-A');
CALL SP_RegistrarSede('QA-DIAMOND-SEDE-B', 'AULA B', 'EDIF B', @IdMun, 40, 1, 1, 0, 0, 0, 0);
SET @IdSedeB = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-B');
CALL SP_RegistrarSede('QA-DIAMOND-SEDE-C', 'VIRTUAL', 'ONLINE', @IdMun, 100, 1, 1, 0, 0, 0, 0);
SET @IdSedeC = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'QA-DIAMOND-SEDE-C');

-- Temas
CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-1', 'SEGURIDAD', 'SEG', 20, 1);
SET @IdTema1 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-1');
CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-2', 'LIDERAZGO', 'LID', 10, 1);
SET @IdTema2 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-2');
CALL SP_RegistrarTemaCapacitacion('QA-DIAMOND-TEMA-3', 'TECNICO', 'TEC', 30, 1);
SET @IdTema3 = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'QA-DIAMOND-TEMA-3');

-- Variables Base
SET @RolAdmin=1; SET @RolCoord=2; SET @RolInst=3; SET @RolPart=4;
SET @IdRegimen = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo LIMIT 1);
SET @IdRegion  = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo LIMIT 1);
SET @IdPuesto  = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo LIMIT 1);
SET @Mod_Pres=1; SET @Mod_Virt=2; SET @Mod_Hib=3;
SET @St_Prog=1; SET @St_PorIni=2; SET @St_EnCurso=3; SET @St_Fin=4; SET @St_Eval=5; 
SET @St_Acr=6; SET @St_NoAcr=7; SET @St_Canc=8; SET @St_Repro=9; SET @St_Arch=10; SET @St_Reprog=9;

-- 2.1 STAFF
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-ADM1', NULL, 'ADMIN', '1', 'QA', '1990-01-01', '2030-01-01', 'a1@d.test', '123', @RolAdmin, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Adm1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-ADM2', NULL, 'ADMIN', '2', 'QA', '1990-01-01', '2030-01-01', 'a2@d.test', '123', @RolAdmin, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Adm2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-ADM2');

CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-COO1', NULL, 'COORD', '1', 'QA', '1990-01-01', '2030-01-01', 'c1@d.test', '123', @RolCoord, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Coo1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-COO2', NULL, 'COORD', '2', 'QA', '1990-01-01', '2030-01-01', 'c2@d.test', '123', @RolCoord, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Coo2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-COO2');

CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-INS1', NULL, 'INST', '1', 'QA', '1990-01-01', '2030-01-01', 'i1@d.test', '123', @RolInst, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Inst1 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS1');
CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, 'QA-DIAMOND-INS2', NULL, 'INST', '2', 'QA', '1990-01-01', '2030-01-01', 'i2@d.test', '123', @RolInst, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
SET @U_Inst2 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-INS2');

SELECT '--- 2.2 Creando 70 Participantes (P01-P70) ---' AS STEP;
-- Usamos un procedimiento temporal para no escribir 70 líneas
DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_Temp_GenUsers`$$
CREATE PROCEDURE `SP_Temp_GenUsers`()
BEGIN
    DECLARE i INT DEFAULT 1;
    WHILE i <= 70 DO
        CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, CONCAT('QA-DIAMOND-P', LPAD(i,2,'0')), NULL, CONCAT('P',i), 'USER', 'QA', '2000-01-01', '2030-01-01', CONCAT('p',i,'@d.test'), '123', 4, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;
CALL `SP_Temp_GenUsers`();
DROP PROCEDURE `SP_Temp_GenUsers`;

-- Variable clave para alumno P01
SET @U_P01 = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'QA-DIAMOND-P01');

SELECT '✅ FASE 2: Actores creados.' AS STATUS;

/* ==========================================================================================================
   FASE 3: CREACIÓN DE LOS 6 CURSOS (PROGRAMADO)
   ========================================================================================================== */
SELECT '--- 3.1 Creando 6 Cursos ---' AS STEP;

-- C01 (30 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C01', @IdGer, @IdTema1, @U_Inst1, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 20 DAY), DATE_ADD(@FechaHoy, INTERVAL 25 DAY), 30, @St_Prog, 'C01 Base');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'));

-- C02 (25 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C02', @IdGer, @IdTema2, @U_Inst2, @IdSedeB, @Mod_Virt, DATE_ADD(@FechaHoy, INTERVAL 22 DAY), DATE_ADD(@FechaHoy, INTERVAL 27 DAY), 25, @St_Prog, 'C02 Base');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'));

-- C03 (30 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C03', @IdGer, @IdTema3, @U_Inst1, @IdSedeC, @Mod_Hib, DATE_ADD(@FechaHoy, INTERVAL 25 DAY), DATE_ADD(@FechaHoy, INTERVAL 30 DAY), 30, @St_Prog, 'C03 Base');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'));

-- C04 (20 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C04', @IdGer, @IdTema1, @U_Inst2, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 30 DAY), DATE_ADD(@FechaHoy, INTERVAL 35 DAY), 20, @St_Prog, 'C04 Base');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'));

-- C05 (15 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C05', @IdGer, @IdTema2, @U_Inst1, @IdSedeB, @Mod_Virt, DATE_ADD(@FechaHoy, INTERVAL 35 DAY), DATE_ADD(@FechaHoy, INTERVAL 40 DAY), 15, @St_Prog, 'C05 Base');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'));

-- C06 (40 Cupos)
CALL SP_RegistrarCapacitacion(@U_Coo2, 'QA-DIAMOND-C06', @IdGer, @IdTema3, @U_Inst2, @IdSedeC, @Mod_Hib, DATE_ADD(@FechaHoy, INTERVAL 40 DAY), DATE_ADD(@FechaHoy, INTERVAL 45 DAY), 40, @St_Prog, 'C06 Base');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'));

SELECT '✅ FASE 3: 6 Cursos creados.' AS STATUS;

/* ==========================================================================================================
   FASE 4: INSCRIPCIÓN Y COLA DE ESPERA (MIXTO)
   ========================================================================================================== */
SELECT '--- 4.1 Inscribiendo Usuarios del Sistema ---' AS STEP;

DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_QA_Enroll`$$
CREATE PROCEDURE `SP_QA_Enroll`(IN _CursoID INT, IN _Start INT, IN _End INT)
BEGIN
    DECLARE i INT DEFAULT _Start;
    DECLARE v_ID INT;
    WHILE i <= _End DO
        SELECT Id_Usuario INTO v_ID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(i,2,'0'));
        CALL SP_RegistrarParticipacionCapacitacion(v_ID, _CursoID); 
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;

-- C01 (30 Cupos): Llenamos 25 con Sistema. 
CALL `SP_QA_Enroll`(@C01_Ver, 1, 25); 
-- C02 (25 Cupos): Llenamos 20 con Sistema.
CALL `SP_QA_Enroll`(@C02_Ver, 26, 45); 
-- C03 (30 Cupos): Llenamos 30 con Sistema (Lleno).
CALL `SP_QA_Enroll`(@C03_Ver, 1, 30); 
-- C04 (20 Cupos): Llenamos 20 con Sistema (Lleno).
CALL `SP_QA_Enroll`(@C04_Ver, 31, 50); 
-- C05 (15 Cupos): Llenamos 15 con Sistema (Lleno).
CALL `SP_QA_Enroll`(@C05_Ver, 1, 15);
-- C06 (40 Cupos): Llenamos 30 con Sistema.
CALL `SP_QA_Enroll`(@C06_Ver, 16, 45);

DROP PROCEDURE `SP_QA_Enroll`;
SELECT '✅ FASE 4: Inscripciones realizadas.' AS STATUS;

/* ==========================================================================================================
   FASE 4.5: TURBULENCIA OPERATIVA (CAOS EN LOS 6 CURSOS)
   ==========================================================================================================
   [OBJETIVO]: En CADA curso, 5 se dan de baja y 3 intentan volver.
   [ADICIONAL]: Si el curso está lleno, el reingreso debe fallar si alguien tomó el lugar.
   ========================================================================================================== */
SELECT '--- 4.5 Caos Administrativo (Bajas y Reingresos Masivos) ---' AS STEP;

DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_QA_Chaos`$$
CREATE PROCEDURE `SP_QA_Chaos`(IN _CursoID INT, IN _StartUser INT, IN _AdminID INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE v_UserID INT;
    DECLARE v_RegID INT;
    
    -- 1. DAR DE BAJA A 5 (Liberar Espacio)
    WHILE i < 5 DO
        SELECT Id_Usuario INTO v_UserID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(_StartUser + i, 2, '0'));
        SELECT Id_CapPart INTO v_RegID FROM Capacitaciones_Participantes WHERE Fk_Id_DatosCap = _CursoID AND Fk_Id_Usuario = v_UserID LIMIT 1;
        -- Ejecutar Baja (Estatus 5)
        IF v_RegID IS NOT NULL THEN
            CALL SP_CambiarEstatusParticipanteCapacitacion(_AdminID, v_RegID, 5, 'QA: Baja Administrativa');
        END IF;
        SET i = i + 1;
    END WHILE;

    -- 2. REINTEGRAR A LOS PRIMEROS 3 (Intento de Reingreso)
    -- Si el curso sigue teniendo cupo, entrarán. Si se llenó en medio (externos), rebotarán.
    SET i = 0;
    WHILE i < 3 DO
        SELECT Id_Usuario INTO v_UserID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(_StartUser + i, 2, '0'));
        SELECT Id_CapPart INTO v_RegID FROM Capacitaciones_Participantes WHERE Fk_Id_DatosCap = _CursoID AND Fk_Id_Usuario = v_UserID LIMIT 1;
        -- Ejecutar Reingreso (Estatus 1)
        IF v_RegID IS NOT NULL THEN
            -- Envolvemos en bloque para que no falle el script si hay cupo lleno
            BEGIN
                DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
                CALL SP_CambiarEstatusParticipanteCapacitacion(_AdminID, v_RegID, 1, 'QA: Reingreso');
            END;
        END IF;
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;

-- Ejecutar Caos en los 6 Cursos
CALL `SP_QA_Chaos`(@C01_Ver, 1, @U_Coo1);
CALL `SP_QA_Chaos`(@C02_Ver, 26, @U_Coo1);
CALL `SP_QA_Chaos`(@C03_Ver, 1, @U_Coo2);
CALL `SP_QA_Chaos`(@C04_Ver, 31, @U_Coo2);
CALL `SP_QA_Chaos`(@C05_Ver, 1, @U_Coo1);
CALL `SP_QA_Chaos`(@C06_Ver, 16, @U_Coo2);

DROP PROCEDURE `SP_QA_Chaos`;

SELECT '✅ FASE 4.5: Turbulencia operativa aplicada a los 6 cursos.' AS STATUS;

/* ==========================================================================================================
   FASE 5: AUTORIZACIÓN (POR INICIAR) + CUPO EXTERNO
   ========================================================================================================== */
SELECT '--- 5.1 Autorizando y Definiendo Cupo Externo ---' AS STEP;

-- C01: Autorizado con 10 externos manuales
CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 20 DAY), DATE_ADD(@FechaHoy, INTERVAL 25 DAY), 10, 'Autorizado');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 22 DAY), DATE_ADD(@FechaHoy, INTERVAL 27 DAY), 15, 'Autorizado');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 25 DAY), DATE_ADD(@FechaHoy, INTERVAL 30 DAY), 5, 'Autorizado');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);

CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst2, @IdSedeA, @Mod_Pres, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 30 DAY), DATE_ADD(@FechaHoy, INTERVAL 35 DAY), 0, 'Autorizado');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);

CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 35 DAY), DATE_ADD(@FechaHoy, INTERVAL 40 DAY), 5, 'Autorizado');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);

CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, @St_PorIni, DATE_ADD(@FechaHoy, INTERVAL 40 DAY), DATE_ADD(@FechaHoy, INTERVAL 45 DAY), 20, 'Autorizado');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

-- [AUDITORÍA VISUAL]: Buscador
CALL SP_BuscadorGlobalPICADE('QA-DIAMOND');

SELECT '✅ FASE 5: Cursos autorizados.' AS STATUS;

/* ==========================================================================================================
   FASE 6: ESCENARIOS DE CAMBIOS Y REPROGRAMACIÓN (HISTORIAL 5 PASOS)
   ========================================================================================================== 
   [OBJETIVO]: Generar historial ROBUSTO (5 cambios) para LOS 6 CURSOS.
   ========================================================================================================== */
SELECT '--- 6.1 Generando Historial Masivo (5 Cambios x 6 Cursos) ---' AS STEP;

DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_QA_HistoryBuilder`$$
CREATE PROCEDURE `SP_QA_HistoryBuilder`(IN _IDVer INT, IN _HeadID INT, IN _CoordID INT, IN _InstID INT, IN _SedeID INT, IN _ModID INT)
BEGIN
    DECLARE v_NewVer INT DEFAULT _IDVer;
    -- Cambio 1: Instructor
    CALL SP_Editar_Capacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, 9, DATE_ADD(CURDATE(), INTERVAL 20 DAY), DATE_ADD(CURDATE(), INTERVAL 25 DAY), 0, 'Cambio Inst');
    SELECT MAX(Id_DatosCap) INTO v_NewVer FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = _HeadID;
    -- Cambio 2: Sede
    CALL SP_Editar_Capacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, 9, DATE_ADD(CURDATE(), INTERVAL 20 DAY), DATE_ADD(CURDATE(), INTERVAL 25 DAY), 0, 'Cambio Sede');
    SELECT MAX(Id_DatosCap) INTO v_NewVer FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = _HeadID;
    -- Cambio 3: Fecha
    CALL SP_Editar_Capacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, 9, DATE_ADD(CURDATE(), INTERVAL 22 DAY), DATE_ADD(CURDATE(), INTERVAL 27 DAY), 0, 'Nueva Fecha');
    SELECT MAX(Id_DatosCap) INTO v_NewVer FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = _HeadID;
    -- Cambio 4: Ajuste
    CALL SP_Editar_Capacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, 9, DATE_ADD(CURDATE(), INTERVAL 22 DAY), DATE_ADD(CURDATE(), INTERVAL 27 DAY), 0, 'Ajuste');
    SELECT MAX(Id_DatosCap) INTO v_NewVer FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = _HeadID;
    -- Cambio 5: Regreso a Por Iniciar
    CALL SP_Editar_Capacitacion(v_NewVer, _CoordID, _InstID, _SedeID, _ModID, 2, DATE_ADD(CURDATE(), INTERVAL 14 DAY), DATE_ADD(CURDATE(), INTERVAL 19 DAY), 0, 'Confirmado');
END$$
DELIMITER ;

-- Ejecutar para los 6 cursos
CALL `SP_QA_HistoryBuilder`(@C01_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C01'), @U_Coo1, @U_Inst2, @IdSedeA, @Mod_Pres);
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

CALL `SP_QA_HistoryBuilder`(@C02_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C02'), @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt);
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

CALL `SP_QA_HistoryBuilder`(@C03_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C03'), @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib);
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);

CALL `SP_QA_HistoryBuilder`(@C04_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C04'), @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres);
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);

CALL `SP_QA_HistoryBuilder`(@C05_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C05'), @U_Coo1, @U_Inst2, @IdSedeB, @Mod_Virt);
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);

CALL `SP_QA_HistoryBuilder`(@C06_Ver, (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C06'), @U_Coo2, @U_Inst1, @IdSedeC, @Mod_Hib);
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

DROP PROCEDURE `SP_QA_HistoryBuilder`;

-- [AUDITORÍA VISUAL]: Historial C01
CALL SP_ConsultarCapacitacionEspecifica(@C01_Ver);

SELECT '✅ FASE 6: Historial profundo generado.' AS STATUS;

/* ==========================================================================================================
   FASE 7: EJECUCIÓN (EN CURSO)
   ========================================================================================================== */
SELECT '--- 7.1 Arrancando Cursos ---' AS STEP;

CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'En Curso');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'En Curso');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Pres, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'En Curso');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);

CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'En Curso');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);

CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'En Curso');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);

CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 3, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'En Curso');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

-- [AUDITORÍA VISUAL]: Instructor ve su carga
CALL SP_ConsultarCursosImpartidos(@U_Inst1);

SELECT '✅ FASE 7: Cursos en ejecución.' AS STATUS;

/* ==========================================================================================================
   FASE 8: EVALUACIÓN (ASENTAMIENTO DE NOTAS)
   ========================================================================================================== */
SELECT '--- 8.1 Cambio Automático a EVALUACIÓN (Los 6 Cursos) ---' AS STEP;

CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Evaluando');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Evaluando');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Evaluando');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);

CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Evaluando');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);

CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Evaluando');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);

CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 5, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Evaluando');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

SELECT '--- 8.2 Asentando Calificaciones Masivas (Vía SP) ---' AS STEP;

DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_QA_Grade`$$
CREATE PROCEDURE `SP_QA_Grade`(IN _CursoID INT, IN _Start INT, IN _End INT, IN _Grade DECIMAL(5,2), IN _Exec INT)
BEGIN
    DECLARE i INT DEFAULT _Start;
    DECLARE v_UID INT;
    DECLARE v_RegID INT;
    WHILE i <= _End DO
        SELECT Id_Usuario INTO v_UID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(i,2,'0'));
        SELECT Id_CapPart INTO v_RegID FROM Capacitaciones_Participantes WHERE Fk_Id_DatosCap = _CursoID AND Fk_Id_Usuario = v_UID LIMIT 1;
        IF v_RegID IS NOT NULL THEN
            CALL SP_EditarParticipanteCapacitacion(_Exec, v_RegID, _Grade, 100.00, NULL, 'Eval QA');
        END IF;
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;

-- C01: Aprobados (P01-P18)
CALL `SP_QA_Grade`(@C01_Ver, 1, 18, 95.00, @U_Inst2);
-- C02: Reprobados (P21-P30)
CALL `SP_QA_Grade`(@C02_Ver, 21, 30, 50.00, @U_Inst1);
-- C03: Aprobados (P31-P55)
CALL `SP_QA_Grade`(@C03_Ver, 31, 55, 90.00, @U_Inst2);
-- C04: Aprobados (P01-P15)
CALL `SP_QA_Grade`(@C04_Ver, 1, 15, 80.00, @U_Inst1);
-- C05: Aprobados (P16-P25)
CALL `SP_QA_Grade`(@C05_Ver, 16, 25, 85.00, @U_Inst1);
-- C06: Aprobados (P26-P45)
CALL `SP_QA_Grade`(@C06_Ver, 26, 45, 92.00, @U_Inst3);

DROP PROCEDURE `SP_QA_Grade`;

-- [AUDITORÍA VISUAL]: Alumno ve sus notas
CALL SP_ConsularMisCursos(@U_P01);

SELECT '✅ FASE 8: Evaluaciones completadas.' AS STATUS;

/* ==========================================================================================================
   FASE 9: DICTAMEN DE ACREDITACIÓN
   ========================================================================================================== */
SELECT '--- 9.1 Aplicando Veredictos ---' AS STEP;

-- C01: Acreditado
CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Dictamen: ACREDITADO');
SET @C01_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C01_Head);

-- C02: No Acreditado
CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 7, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Dictamen: NO ACREDITADO');
SET @C02_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C02_Head);

-- C03: Acreditado
CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Hib, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Dictamen: ACREDITADO');
SET @C03_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C03_Head);

-- C04: Acreditado
CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Dictamen: ACREDITADO');
SET @C04_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C04_Head);

-- C05: Acreditado
CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Dictamen: ACREDITADO');
SET @C05_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C05_Head);

-- C06: Acreditado
CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst3, @IdSedeC, @Mod_Hib, 6, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Dictamen: ACREDITADO');
SET @C06_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C06_Head);

SELECT '✅ FASE 9: Veredictos aplicados.' AS STATUS;

/* ==========================================================================================================
   FASE 10: CIERRE (FINALIZADO)
   ========================================================================================================== */
SELECT '--- 10.1 Cierre Final ---' AS STEP;

CALL SP_Editar_Capacitacion(@C01_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 10, 'Cierre');
CALL SP_Editar_Capacitacion(@C02_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 15, 'Cierre');
CALL SP_Editar_Capacitacion(@C03_Ver, @U_Coo2, @U_Inst2, @IdSedeC, @Mod_Pres, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Cierre');
CALL SP_Editar_Capacitacion(@C04_Ver, @U_Coo2, @U_Inst1, @IdSedeA, @Mod_Pres, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 0, 'Cierre');
CALL SP_Editar_Capacitacion(@C05_Ver, @U_Coo1, @U_Inst1, @IdSedeB, @Mod_Virt, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 5, 'Cierre');
CALL SP_Editar_Capacitacion(@C06_Ver, @U_Coo2, @U_Inst3, @IdSedeC, @Mod_Hib, 4, DATE_ADD(@FechaHoy, INTERVAL 14 DAY), DATE_ADD(@FechaHoy, INTERVAL 19 DAY), 20, 'Cierre');

-- [AUDITORÍA VISUAL]: Resumen Anual
CALL SP_Dashboard_ResumenAnual();

SELECT '✅ FASE 10: Cierre completado.' AS STATUS;

/* ==========================================================================================================
   FASE 11: ARCHIVADO
   ========================================================================================================== */
SELECT '--- 11.1 Archivando ---' AS STEP;

CALL SP_CambiarEstatusCapacitacion(@C01_Head, @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion(@C02_Head, @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion(@C03_Head, @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion(@C04_Head, @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion(@C05_Head, @U_Adm1, 0);
CALL SP_CambiarEstatusCapacitacion(@C06_Head, @U_Adm1, 0);

SELECT '✅ FASE 11: Archivado completado.' AS STATUS;

/* ==========================================================================================================
   FASE 12: CANCELACIÓN
   ========================================================================================================== */
SELECT '--- 12.1 Prueba Cancelación ---' AS STEP;
CALL SP_RegistrarCapacitacion(@U_Coo1, 'QA-DIAMOND-C07', @IdGer, @IdTema1, @U_Inst1, @IdSedeA, @Mod_Pres, DATE_ADD(@FechaHoy, INTERVAL 90 DAY), DATE_ADD(@FechaHoy, INTERVAL 95 DAY), 30, @St_Prog, 'C07 Cancel');
SET @C07_Head = (SELECT Id_Capacitacion FROM Capacitaciones WHERE Numero_Capacitacion = 'QA-DIAMOND-C07');
SET @C07_Ver = (SELECT MAX(Id_DatosCap) FROM DatosCapacitaciones WHERE Fk_Id_Capacitacion = @C07_Head);
CALL SP_RegistrarParticipanteCapacitacion(@U_Adm1, @C07_Ver, @U_P01);
CALL SP_Editar_Capacitacion(@C07_Ver, @U_Coo1, @U_Inst1, @IdSedeA, @Mod_Pres, 8, DATE_ADD(@FechaHoy, INTERVAL 90 DAY), DATE_ADD(@FechaHoy, INTERVAL 95 DAY), 0, 'Cancelado');
CALL SP_CambiarEstatusCapacitacion(@C07_Head, @U_Adm1, 0);

SELECT '✅ FASE 12: Cancelación completada.' AS STATUS;

/* ==========================================================================================================
   FASE 14: LIMPIEZA FINAL
   ========================================================================================================== */
SELECT '--- 14.1 Limpieza Final ---' AS STEP;
DELETE FROM Capacitaciones_Participantes WHERE Fk_Id_Usuario IN (SELECT Id_Usuario FROM Usuarios WHERE Ficha LIKE 'QA-DIAMOND%');
CALL SP_EliminarCapacitacion(@C01_Head);
CALL SP_EliminarCapacitacion(@C02_Head);
CALL SP_EliminarCapacitacion(@C03_Head);
CALL SP_EliminarCapacitacion(@C04_Head);
CALL SP_EliminarCapacitacion(@C05_Head);
CALL SP_EliminarCapacitacion(@C06_Head);
CALL SP_EliminarCapacitacion(@C07_Head);

DELIMITER $$
DROP PROCEDURE IF EXISTS `SP_Temp_DelUsers`$$
CREATE PROCEDURE `SP_Temp_DelUsers`()
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE v_ID INT;
    WHILE i <= 70 DO
        SELECT Id_Usuario INTO v_ID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(i,2,'0'));
        IF v_ID IS NOT NULL THEN CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, v_ID); END IF;
        SET i = i + 1;
    END WHILE;
END$$
DELIMITER ;
CALL `SP_Temp_DelUsers`();
DROP PROCEDURE `SP_Temp_DelUsers`;

CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Adm1);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Adm2);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Coo1);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Coo2);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Inst1);
CALL SP_EliminarUsuarioDefinitivamente(@AdminEjecutor, @U_Inst2);

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

SELECT '✅ FASE 14: Limpieza completada.' AS STATUS;