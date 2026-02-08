
/*
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

DELIMITER ;*/

/*
DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_QA_Grade`$$

CREATE PROCEDURE `SP_QA_Grade`(
    IN _CursoID INT, 
    IN _Start INT, 
    IN _End INT, 
    IN _Grade DECIMAL(5,2), 
    IN _Exec INT
)
BEGIN
    DECLARE i INT DEFAULT _Start;
    DECLARE v_UID INT;
    DECLARE v_RegID INT;
    DECLARE v_StatusActual INT; -- Nueva variable para checar el estado
    
    WHILE i <= _End DO
        -- 1. Obtenemos ID de Usuario
        SELECT Id_Usuario INTO v_UID FROM Usuarios WHERE Ficha = CONCAT('QA-DIAMOND-P', LPAD(i,2,'0'));
        
        -- 2. Obtenemos ID de Registro y SU ESTATUS ACTUAL
        SET v_RegID = NULL;
        SELECT Id_CapPart, Fk_Id_CatEstPart 
        INTO v_RegID, v_StatusActual 
        FROM Capacitaciones_Participantes 
        WHERE Fk_Id_DatosCap = _CursoID AND Fk_Id_Usuario = v_UID LIMIT 1;
        
        -- 3. Lógica de Salto Inteligente
        IF v_RegID IS NOT NULL THEN
            -- [CONDICIÓN]: Si NO es Baja (5), procedemos a calificar.
            IF v_StatusActual != 5 THEN
                CALL SP_EditarParticipanteCapacitacion(_Exec, v_RegID, _Grade, 100.00, NULL, 'Eval QA');
            ELSE
                -- (Opcional) Mensaje de depuración solo para saber a quién saltamos
                SELECT CONCAT('SKIPPING: Usuario P', i, ' está en BAJA. No se califica.') AS Info;
            END IF;
        END IF;
        
        SET i = i + 1;
    END WHILE;
END$$

DELIMITER ;*/

-- Reutilizamos el Helper Silencioso que ya tienes (SP_QA_Grade)

-- =================================================================================================
-- C01 (Inscritos: P01 a P25)
-- =================================================================================================
-- Objetivo: Mayoría Aprobada (Calificamos a todos del 1 al 25)
CALL `SP_QA_Grade`(@C01_Ver, 1, 25, 95.00, @U_Inst2);

-- =================================================================================================
-- C02 (Inscritos: P26 a P45)
-- =================================================================================================
-- Objetivo: Mayoría Reprobada (Calificamos a todos del 26 al 45)
-- Nota: Esto cubrirá tus 18 alumnos vivos (20 inscritos - 2 bajas aprox)
CALL `SP_QA_Grade`(@C02_Ver, 26, 45, 50.00, @U_Inst1);

-- =================================================================================================
-- C03 (Inscritos: P01 a P30) -> OJO: Es un grupo híbrido que comparte alumnos con C01
-- =================================================================================================
-- Objetivo: 100% Aprobación
CALL `SP_QA_Grade`(@C03_Ver, 1, 30, 90.00, @U_Inst2);

-- =================================================================================================
-- C04 (Inscritos: P31 a P50)
-- =================================================================================================
-- Objetivo: Mixto (Aprobamos con 80)
CALL `SP_QA_Grade`(@C04_Ver, 31, 50, 80.00, @U_Inst1);

-- =================================================================================================
-- C05 (Inscritos: P01 a P15) -> Grupo pequeño
-- =================================================================================================
-- Objetivo: Aprobados
CALL `SP_QA_Grade`(@C05_Ver, 1, 15, 85.00, @U_Inst1);

-- =================================================================================================
-- C06 (Inscritos: P16 a P45) -> Grupo grande masivo
-- =================================================================================================
-- Objetivo: Excelencia (92.00)
CALL `SP_QA_Grade`(@C06_Ver, 16, 45, 92.00, @U_Inst2);
