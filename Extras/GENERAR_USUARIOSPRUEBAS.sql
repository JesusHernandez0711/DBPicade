/*
DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Temp_GenUsers`$$

CREATE PROCEDURE `SP_Temp_GenUsers`()
BEGIN
    DECLARE i INT DEFAULT 1;
    WHILE i <= 70 DO
        -- Inserción individual simulando una alta manual por parte del Admin
        CALL SP_RegistrarUsuarioPorAdmin(@AdminEjecutor, CONCAT('QA-DIAMOND-P', LPAD(i,2,'0')), NULL, CONCAT('P',i), 'USER', 'QA', '1980-01-01', '2015-01-01', CONCAT('p',i,'@d.test'), '123', @RolPart, @IdRegimen, @IdPuesto, @IdCT, @IdDep, @IdRegion, @IdGer, '01', 'A');
        SET i = i + 1;
    END WHILE;
END$$

DELIMITER ;

DELIMITER $$

DROP PROCEDURE IF EXISTS `SP_Temp_GenUsers`$$

CREATE PROCEDURE `SP_Temp_GenUsers`()
BEGIN
    DECLARE i INT DEFAULT 1;
    
    -- =============================================
    -- 1. VARIABLES PARA FECHAS (Lógica Anterior)
    -- =============================================
    DECLARE v_FecNac DATE;
    DECLARE v_FecIng DATE;
    DECLARE v_Min_Fecha_Ingreso DATE;
    DECLARE v_Dias_Rango INT;
    DECLARE v_Tope_Nacimiento DATE DEFAULT '1995-12-31';
    DECLARE v_Base_Nacimiento DATE DEFAULT '1970-01-01';
    DECLARE v_Tope_Ingreso    DATE DEFAULT '2023-01-01';

    -- =============================================
    -- 2. VARIABLES PARA NOMBRES (Nueva Lógica)
    -- =============================================
    DECLARE v_ListaNombres JSON;
    DECLARE v_ListaApellidos JSON;
    DECLARE v_NombreRand VARCHAR(100);
    DECLARE v_ApellidoRand VARCHAR(100);
    DECLARE v_TotalNombres INT;
    DECLARE v_TotalApellidos INT;
    DECLARE v_NombreCompleto VARCHAR(150);
    
    -- =============================================
    -- 3. CARGA DE DATOS (Aquí puedes pegar tu lista)
    -- =============================================
    -- Lista de 30 Nombres Comunes
    SET v_ListaNombres = '["Sofía", "Santiago", "Camila", "Sebastián", "Valentina", "Mateo", "Isabella", "Nicolás", "Lucía", "Alejandro", "Mariana", "Diego", "Gabriela", "Samuel", "Victoria", "Daniel", "Martina", "Leonardo", "Luciana", "Eduardo", "Daniela", "Carlos", "Andrea", "Felipe", "Natalia", "Javier", "Valeria", "Luis", "Fernanda", "Adrián"]';
    
    -- Lista de 30 Apellidos Comunes
    SET v_ListaApellidos = '["García", "Rodríguez", "Martínez", "Hernández", "López", "González", "Pérez", "Sánchez", "Ramírez", "Torres", "Flores", "Rivera", "Gómez", "Díaz", "Reyes", "Morales", "Ortiz", "Castillo", "Moreno", "Vargas", "Romero", "Mendoza", "Ruiz", "Herrera", "Medina", "Aguilar", "Castro", "Jiménez", "Ramos", "Vázquez"]';

    -- Calculamos cuántos hay para saber el límite del RAND
    SET v_TotalNombres = JSON_LENGTH(v_ListaNombres);
    SET v_TotalApellidos = JSON_LENGTH(v_ListaApellidos);

    -- =============================================
    -- 4. INICIO DEL BUCLE
    -- =============================================
    WHILE i <= 70 DO
        
        -- A) GENERACIÓN DE FECHAS (Tu lógica validada)
        SET v_Dias_Rango = DATEDIFF(v_Tope_Nacimiento, v_Base_Nacimiento);
        SET v_FecNac = DATE_ADD(v_Base_Nacimiento, INTERVAL FLOOR(RAND() * v_Dias_Rango) DAY);
        SET v_Min_Fecha_Ingreso = DATE_ADD(v_FecNac, INTERVAL 20 YEAR);

        IF v_Min_Fecha_Ingreso > v_Tope_Ingreso THEN
             SET v_Min_Fecha_Ingreso = DATE_SUB(v_Tope_Ingreso, INTERVAL 1 DAY);
        END IF;

        SET v_Dias_Rango = DATEDIFF(v_Tope_Ingreso, v_Min_Fecha_Ingreso);
        SET v_FecIng = DATE_ADD(v_Min_Fecha_Ingreso, INTERVAL FLOOR(RAND() * v_Dias_Rango) DAY);

        -- B) SELECCIÓN ALEATORIA DE NOMBRE Y APELLIDO
        -- Extraemos un elemento del array JSON usando un índice aleatorio (0 a Total-1)
        SET v_NombreRand = JSON_UNQUOTE(JSON_EXTRACT(v_ListaNombres, CONCAT('$[', FLOOR(RAND() * v_TotalNombres), ']')));
        SET v_ApellidoRand = JSON_UNQUOTE(JSON_EXTRACT(v_ListaApellidos, CONCAT('$[', FLOOR(RAND() * v_TotalApellidos), ']')));
        
        -- Armamos el nombre (Ej: "Santiago P.") para el campo "Nombre" y usamos el apellido completo en "ApellidoPaterno"
        -- Nota: Ajusta según cómo quieras llenar los campos del SP
        
        -- C) LLAMADA AL SP (Inyección de datos dinámicos)
        CALL SP_RegistrarUsuarioPorAdmin(
            @AdminEjecutor, 
            CONCAT('QA-DIAMOND-P', LPAD(i,2,'0')),  -- Ficha
            NULL,                                   -- Huella
            -- CONCAT(v_NombreRand, ' ', v_ApellidoRand), -- Nombre (Aquí concatené para dar variedad)
            CONCAT(v_NombreRand, ' ', v_NombreRand),
            v_ApellidoRand,                         -- Apellido Paterno (Reciclado para el ejemplo)
            'QA',                                   -- Apellido Materno
            v_FecNac,                               -- Fecha Nacimiento Dinámica
            v_FecIng,                               -- Fecha Ingreso Dinámica
            CONCAT('p',i,'@d.test'),                -- Email secuencial (mejor para QA)
            '123', 
            @RolPart, 
            @IdRegimen, 
            @IdPuesto, 
            @IdCT2, 
            @IdDep2, 
            @IdRegion, 
            @IdGer2, 
            '01', 
            'A'
        );
        
        SET i = i + 1;
    END WHILE;
END$$

DELIMITER ;*/