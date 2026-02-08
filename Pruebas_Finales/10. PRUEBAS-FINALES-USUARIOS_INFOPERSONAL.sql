USE Picade;

/* ====================================================================================================
   SCRIPT MAESTRO DE PRUEBAS DE ACEPTACIÓN DE USUARIO (UAT - USER ACCEPTANCE TESTING)
   ====================================================================================================
   AUTOR:       Arquitectura de Datos PICADE
   OBJETIVO:    Validar el ciclo de vida completo de la identidad digital, asegurando la integridad
                referencial, los candados operativos y la seguridad de la información.
   ESTRATEGIA:  "SANDBOX ISOLATION" (Aislamiento de Entorno).
                Se crean 3 sets completos de datos ficticios (A, B, C) para no contaminar ni poner 
                en riesgo la información real cargada previamente vía CSV.
   ==================================================================================================== */

/* ----------------------------------------------------------------------------------------------------
   CONFIGURACIÓN INICIAL DEL EJECUTOR
   Definimos quién es el "Dios" o Super-Admin que orquestará las pruebas.
   ⚠️ IMPORTANTE: Asegúrate de que este ID exista en tu tabla Usuarios.
   ---------------------------------------------------------------------------------------------------- */
SET @IdAdminGod = 322; 


/* ====================================================================================================
   FASE 0: INFRAESTRUCTURA DEL SANDBOX (CONSTRUCCIÓN DE ESCENARIOS)
   Creamos 3 universos paralelos de catálogos para probar movilidad extrema y cambios parciales.
   ==================================================================================================== */

/* --------------------------------------------------------------------------------
   0.1. CONSTRUCCIÓN DEL SET "A" (ESCENARIO ORIGINAL)
   -------------------------------------------------------------------------------- */
-- Geografía
CALL SP_RegistrarUbicaciones('M_QA_A', 'MUN A', 'E_QA_A', 'EDO A', 'P_QA_A', 'PAIS A');
SET @MunA = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'M_QA_A');

-- Organización
CALL SP_RegistrarOrganizacion('G_QA_A', 'GER A', 'S_QA_A', 'SUB A', 'D_QA_A', 'DIR A');
SET @GerenA = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'G_QA_A');

-- Catálogos Laborales
CALL SP_RegistrarRegimen('REG-A', 'REGIMEN A', 'X');
SET @RegA = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo WHERE Codigo = 'REG-A');

CALL SP_RegistrarRegion('RGN-A', 'REGION A', 'X');
SET @RgnA = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo WHERE Codigo = 'RGN-A');

CALL SP_RegistrarCentroTrabajo('CT-A', 'CT A', 'X', @MunA);
SET @CTA = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'CT-A');

CALL SP_RegistrarDepartamento('DEP-A', 'DEP A', 'X', @MunA);
SET @DepA = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'DEP-A');

CALL SP_RegistrarPuesto('PUE-A', 'PUESTO A', 'X');
SET @PueA = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo WHERE Codigo = 'PUE-A');


/* --------------------------------------------------------------------------------
   0.2. CONSTRUCCIÓN DEL SET "B" (ESCENARIO DE MUDANZA 1)
   -------------------------------------------------------------------------------- */
-- Geografía
CALL SP_RegistrarUbicaciones('M_QA_B', 'MUN B', 'E_QA_B', 'EDO B', 'P_QA_B', 'PAIS B');
SET @MunB = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'M_QA_B');

-- Organización
CALL SP_RegistrarOrganizacion('G_QA_B', 'GER B', 'S_QA_B', 'SUB B', 'D_QA_B', 'DIR B');
SET @GerenB = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'G_QA_B');

-- Catálogos Laborales
CALL SP_RegistrarRegimen('REG-B', 'REGIMEN B', 'X');
SET @RegB = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo WHERE Codigo = 'REG-B');

CALL SP_RegistrarRegion('RGN-B', 'REGION B', 'X');
SET @RgnB = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo WHERE Codigo = 'RGN-B');

CALL SP_RegistrarCentroTrabajo('CT-B', 'CT B', 'X', @MunB);
SET @CTB = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'CT-B');

CALL SP_RegistrarDepartamento('DEP-B', 'DEP B', 'X', @MunB);
SET @DepB = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'DEP-B');

CALL SP_RegistrarPuesto('PUE-B', 'PUESTO B', 'X');
SET @PueB = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo WHERE Codigo = 'PUE-B');


/* --------------------------------------------------------------------------------
   0.3. CONSTRUCCIÓN DEL SET "C" (ESCENARIO DE MUDANZA 2)
   -------------------------------------------------------------------------------- */
-- Geografía
CALL SP_RegistrarUbicaciones('M_QA_C', 'MUN C', 'E_QA_C', 'EDO C', 'P_QA_C', 'PAIS C');
SET @MunC = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'M_QA_C');

-- Organización
CALL SP_RegistrarOrganizacion('G_QA_C', 'GER C', 'S_QA_C', 'SUB C', 'D_QA_C', 'DIR C');
SET @GerenC = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'G_QA_C');

-- Catálogos Laborales
CALL SP_RegistrarRegimen('REG-C', 'REGIMEN C', 'X');
SET @RegC = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo WHERE Codigo = 'REG-C');

CALL SP_RegistrarRegion('RGN-C', 'REGION C', 'X');
SET @RgnC = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo WHERE Codigo = 'RGN-C');

CALL SP_RegistrarCentroTrabajo('CT-C', 'CT C', 'X', @MunC);
SET @CTC = (SELECT Id_CatCT FROM Cat_Centros_Trabajo WHERE Codigo = 'CT-C');

CALL SP_RegistrarDepartamento('DEP-C', 'DEP C', 'X', @MunC);
SET @DepC = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'DEP-C');

CALL SP_RegistrarPuesto('PUE-C', 'PUESTO C', 'X');
SET @PueC = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo WHERE Codigo = 'PUE-C');


/* --------------------------------------------------------------------------------
   0.4. ACTIVOS DE CAPACITACIÓN (PARA CANDADOS OPERATIVOS)
   Necesarios para simular la asignación de cursos.
   -------------------------------------------------------------------------------- */
INSERT IGNORE INTO `Cat_Tipo_Capacitacion` (Nombre) VALUES ('TIPO QA');
SET @IdTipoCapQA = (SELECT Id_CatTipoCap FROM Cat_Tipo_Capacitacion WHERE Nombre = 'TIPO QA');

INSERT IGNORE INTO `Cat_Capacitacion` (Nombre, Duracion_Horas, Fk_Id_CatTipoCap) VALUES ('CURSO QA BLOQUEO', 10, @IdTipoCapQA);
SET @IdCatCapQA = (SELECT Id_CatCap FROM Cat_Capacitacion WHERE Nombre = 'CURSO QA BLOQUEO');

INSERT IGNORE INTO `Cat_Modalidad_Capacitacion` (Nombre) VALUES ('MODALIDAD QA');
SET @IdModalQA = (SELECT Id_CatModalCap FROM Cat_Modalidad_Capacitacion WHERE Nombre = 'MODALIDAD QA');


/* ====================================================================================================
   FASE 1: PROVISIÓN DE IDENTIDAD (EL "CUARTETO" DE ROLES)
   Objetivo: Validar los dos métodos de ingreso (Auto-Registro y Registro Administrativo).
   ==================================================================================================== */

-- 1.1. USUARIO PARTICIPANTE (Auto-Registro desde el Portal Público)
-- [ESPERADO]: Mensaje 'ÉXITO...', Accion 'CREADA'.
CALL SP_RegistrarUsuarioNuevo(
    'F-PART-QA', 
    'part_qa@test.com', 
    'pass123', 
    'JUAN', 
    'PARTICIPANTE', 
    'QA', 
    '1995-01-01', 
    '2020-01-01'
);
SET @IdUserPart = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'F-PART-QA');


-- 1.2. USUARIO INSTRUCTOR (Registro Administrativo Completo - SET A)
-- [ESPERADO]: Mensaje 'ÉXITO...', Accion 'CREADA'.
CALL SP_RegistrarUsuarioPorAdmin(
    @IdAdminGod, 
    'F-INST-QA',
    NULL,
    'MARIA', 
    'INSTRUCTORA', 
    'QA', 
    '1985-05-05', 
    '2010-01-01',
	'inst_qa@test.com', 
    'pass123', 
    3, -- ROL 3 = INSTRUCTOR
    @RegA, 
    @PueA, 
    @CTA, 
    @DepA, 
    @RgnA, 
    @GerenA, 
    'N35', 
    'CONF'
);
SET @IdUserInst = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'F-INST-QA');


-- 1.3. USUARIO COORDINADOR (Registro Administrativo Completo - SET A)
-- [ESPERADO]: Mensaje 'ÉXITO...', Accion 'CREADA'.
CALL SP_RegistrarUsuarioPorAdmin(
    @IdAdminGod, 
    'F-COORD-QA', 
    NULL,
    'CARLOS', 
    'COORDINADOR', 
    'QA', 
    '1980-01-01', 
    '2005-01-01',
    'coord_qa@test.com', 
    'pass123', 
    2, -- ROL 2 = COORDINADOR
    @RegA, 
    @PueA, 
    @CTA, 
    @DepA, 
    @RgnA, 
    @GerenA, 
    'N40', 
    'CONF'
);
SET @IdUserCoord = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'F-COORD-QA');


-- 1.4. USUARIO ADMINISTRADOR (Registro Administrativo Completo - SET A)
-- [ESPERADO]: Mensaje 'ÉXITO...', Accion 'CREADA'.
CALL SP_RegistrarUsuarioPorAdmin(
    @IdAdminGod, 
    'F-ADMIN-QA',
    NULL, 
    'LAURA', 
    'ADMINISTRADORA', 
    'QA', 
    '1990-01-01', 
    '2015-01-01',
    'admin_qa@test.com', 
    'pass123', 
    1, -- ROL 1 = ADMINISTRADOR
    @RegA, 
    @PueA, 
    @CTA, 
    @DepA, 
    @RgnA, 
    @GerenA, 
    'N44', 
    'CONF'
);
SET @IdUserAdmin = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'F-ADMIN-QA');


/* ====================================================================================================
   FASE 2: VISIBILIDAD Y REPORTES (LECTURA DE DATOS)
   Objetivo: Confirmar que los datos persisten y las vistas los recuperan con los JOINs correctos.
   ==================================================================================================== */

-- 2.1. Ver Vista General (Grid del Panel de Control)
-- [ESPERADO]: Deben aparecer los 4 usuarios nuevos con su Rol y Estatus correctos.
SELECT * FROM Vista_Usuarios_Admin WHERE Ficha_Usuario LIKE '%-QA';

-- 2.2. Simulación: Juan (Participante) ve su propio perfil
-- [ESPERADO]: JSON limpio con los datos personales de Juan.
CALL SP_ConsultarPerfilPropio(@IdUserPart);

-- 2.3. Simulación: Admin inspecciona a Maria (Instructor)
-- [ESPERADO]: JSON completo con auditoría (Debe decir "Creado Por: [Nombre de tu Admin]").
CALL SP_ConsultarUsuarioPorAdmin(@IdUserInst);

-- 2.4. Simulación: Cargar Dropdown para asignar curso
-- [ESPERADO]: Debe aparecer Maria (F-INST-QA). NO debe aparecer Juan (Participante).
CALL SP_ListarInstructoresActivos();


/* ====================================================================================================
   FASE 3: PRUEBAS DE ESTRÉS DE EDICIÓN (MOVILIDAD Y MEZCLA DE DATOS)
   Objetivo: Validar que el sistema soporte cambios masivos y parciales de información.
   Sujeto de prueba: MARIA INSTRUCTORA (@IdUserInst).
   ==================================================================================================== */

-- 3.1. ESCENARIO: EL USUARIO CAMBIA TODA SU PROPIA INFO (SET A -> SET B)
-- [CONTEXTO]: Maria se muda y actualiza su perfil desde el portal.
-- [ESPERADO]: Mensaje 'ÉXITO: Se ha actualizado: ...'
CALL SP_EditarPerfilPropio(
    @IdUserInst,
    'F-INST-QA-B', 
    'foto_B.jpg',    -- Identidad B (Email no cambia aquí)
    'MARIA', 
    'INSTRUCTORA', 
    'BETA', -- Personales B
    '1985-05-05', 
    '2010-01-01',
    @RegB, 
    @PueB, 
    @CTB, 
    @DepB, 
    @RgnB, 
    @GerenB, -- Laborales SET B
    'NIVEL B', 
    'CONF B'
);
-- Verificación Visual: Todo debe apuntar al SET B
CALL SP_ConsultarPerfilPropio(@IdUserInst);

-- 3.2. ESCENARIO: EL ADMIN CAMBIA TODA LA INFO DE OTRO USUARIO (SET B -> SET C)
-- [CONTEXTO]: RH decide mover a Maria a una nueva sucursal (SET C) y corregir su correo.
-- [ESPERADO]: Mensaje 'ÉXITO: Se ha actualizado: ...'
CALL SP_EditarUsuarioPorAdmin(
    @IdAdminGod, 
    @IdUserInst,
    'F-INST-QA-C', 
    'foto_C.jpg',
    'MARIA', 
    'INSTRUCTORA', 
    'GAMMA', 
    '1985-05-05', 
    '2010-01-01',
    'inst_qa_c@test.com', 
    'new_pass_c', -- Cambio de credenciales y password
    3, -- Mantiene Rol Instructor
    @RegC, 
    @PueC, 
    @CTC, 
    @DepC, 
    @RgnC, 
    @GerenC, -- Laborales SET C
    'NIVEL C', 
    'CONF C'
);
-- Verificación Visual: Todo debe apuntar al SET C
CALL SP_ConsultarUsuarioPorAdmin(@IdUserInst);


-- 3.3. ESCENARIO: EL USUARIO CAMBIA CASI TODA SU INFO (PARCIAL / MEZCLA)
-- [CONTEXTO]: Maria corrige su Foto y su Puesto (regresa al A), pero deja el resto igual (C).
-- [ESPERADO]: Mensaje 'ÉXITO: Se ha actualizado: Foto de Perfil, Datos Laborales.' (Solo esos 2)
CALL SP_EditarPerfilPropio(
    @IdUserInst,
    'F-INST-QA-C',      -- Ficha: IGUAL (C)
    'foto_A_mix.jpg',   -- Foto: CAMBIA (A)
    'MARIA', 
    'INSTRUCTORA', 
    'GAMMA', 
    '1985-05-05', 
    '2010-01-01', -- Personales: IGUALES (C)
    @RegC,              -- Regimen: IGUAL
    @PueA,              -- Puesto: CAMBIA (A)
    @CTC,
    @DepC, 
    @RgnC, 
    @GerenC, -- Resto Adscripción: IGUALES (C)
    'NIVEL C', 
    'CONF C'
);
-- Verificación Visual: Puesto es A, Foto es A, el resto es C.
CALL SP_ConsultarPerfilPropio(@IdUserInst);


-- 3.4. ESCENARIO: EL ADMIN CAMBIA CASI TODA LA INFO (MEZCLA FINAL)
-- [CONTEXTO]: Admin cambia Departamento -> B y Gerencia -> B, respetando el Puesto que eligió Maria.
-- [ESPERADO]: Mensaje 'ÉXITO: Se ha actualizado: Adscripción Laboral.'
CALL SP_EditarUsuarioPorAdmin(
    @IdAdminGod, 
    @IdUserInst,
    'F-INST-QA-C', 
    'foto_A_mix.jpg', -- Identidad: IGUALES
    'MARIA', 
    'INSTRUCTORA', 
    'GAMMA', 
    '1985-05-05', 
    '2010-01-01',
    'inst_qa_c@test.com', 
    NULL,      -- Email IGUAL, Pass NULL (No tocar)
    3, -- Rol: IGUAL
    @RegC, 
    @PueA, -- Puesto: IGUAL (A)
    @CTC, 
    @DepB, -- Departamento: CAMBIA a B
    @RgnC, 
    @GerenB, -- Gerencia: CAMBIA a B
    'NIVEL C', 
    'CONF C'
);
-- Verificación Visual Final (El "Frankenstein"): Puesto A, Depto B, Regimen C.
CALL SP_ConsultarUsuarioPorAdmin(@IdUserInst);


/* ====================================================================================================
   FASE 4: SEGURIDAD Y AUTO-GESTIÓN
   Objetivo: Validar que los usuarios puedan cambiar sus credenciales sin romper la unicidad.
   ==================================================================================================== 

-- 4.1. Juan intenta ponerse el email de Maria (Colisión de Identidad)
-- [ESPERADO]: 🔴 ERROR [409]: "...El nuevo correo electrónico ya pertenece a otra cuenta."
CALL SP_ActualizarCredencialesPropio(@IdUserPart, 'inst_qa_c@test.com', NULL);

-- 4.2. Juan cambia su contraseña exitosamente
-- [ESPERADO]: Mensaje 'SEGURIDAD ACTUALIZADA: Se modificó: Contraseña.'
CALL SP_ActualizarCredencialesPropio(@IdUserPart, NULL, 'new_hash_juan_seguro');

*/
/* ====================================================================================================
   FASE 4: SEGURIDAD, AUTO-GESTIÓN Y VALIDACIÓN ESTRICTA
   Objetivo: Validar unicidad, listas blancas de dominios y complejidad de contraseñas.
   Sujeto de prueba: JUAN PARTICIPANTE (@IdUserPart).
   ==================================================================================================== */

-- 4.1. UNICIDAD: Juan intenta ponerse el email de Maria (Colisión de Identidad)
-- [ESPERADO]: 🔴 ERROR [409]: "...El correo ya pertenece a otra cuenta."
CALL SP_ActualizarCredencialesPropio(@IdUserPart, 'inst_qa_c@test.com', NULL);

-- 4.2. DOMINIO INVÁLIDO: Juan intenta usar un correo de Yahoo (No permitido)
-- [ESPERADO]: 🔴 ERROR [400]: "...El correo debe ser institucional (Pemex) o de proveedores autorizados..."
CALL SP_ActualizarCredencialesPropio(@IdUserPart, 'juan_hacker@yahoo.com', NULL);

-- 4.3. DOMINIO VÁLIDO: Juan cambia su correo exitosamente a un dominio permitido
-- [ESPERADO]: Mensaje 'SEGURIDAD ACTUALIZADA: Se modificó: Correo Electrónico.'
CALL SP_ActualizarCredencialesPropio(@IdUserPart, 'juan_nuevo@outlook.es', NULL);

-- 4.4. PASSWORD DÉBIL (Longitud): Menos de 8 caracteres
-- [ESPERADO]: 🔴 ERROR [400]: "...La contraseña debe tener más de 8 caracteres."
CALL SP_ActualizarCredencialesPropio(@IdUserPart, NULL, 'Patito1');

-- 4.5. PASSWORD DÉBIL (Complejidad): Solo letras minúsculas y números (Falta Mayúscula y Especial)
-- [ESPERADO]: 🔴 ERROR [400]: "...La contraseña debe contener al menos una letra MAYÚSCULA."
CALL SP_ActualizarCredencialesPropio(@IdUserPart, NULL, 'patito1234');

-- 4.6. PASSWORD DÉBIL (Complejidad): Falta Caracter Especial
-- [ESPERADO]: 🔴 ERROR [400]: "...La contraseña debe contener al menos un CARÁCTER ESPECIAL..."
CALL SP_ActualizarCredencialesPropio(@IdUserPart, NULL, 'Patito1234');

-- 4.7. PASSWORD ROBUSTO: Cumple con todo (>8, Mayus, Minus, Num, Especial)
-- [ESPERADO]: Mensaje 'SEGURIDAD ACTUALIZADA: Se modificó: Contraseña.'
CALL SP_ActualizarCredencialesPropio(@IdUserPart, NULL, 'P@tito_2025_Seguro');

/* ====================================================================================================
   FASE 5: EL CANDADO OPERATIVO (BLOQUEO POR CURSOS VIVOS)
   Objetivo: Verificar la "Regla de Oro": Nadie se va si tiene trabajo pendiente.
   ==================================================================================================== */

-- 5.1. Preparación: Crear Curso y Asignar Roles
INSERT INTO `Capacitaciones` (Numero_Capacitacion, Fk_Id_CatGeren, Fk_Id_CatCap, Asistentes_Programados) 
VALUES ('CAP-QA-001', @GerenA, @IdCatCapQA, 10);
SET @IdCapQA = LAST_INSERT_ID();

-- Asignar Instructor (MARIA - @IdUserInst) - Estatus 1 (PROGRAMADO/VIVO)
INSERT INTO `DatosCapacitaciones` (Fk_Id_Capacitacion, Fk_Id_Instructor, Fecha_Inicio, Fecha_Fin, Fk_Id_CatCases_Sedes, Fk_Id_CatModalCap, Fk_Id_CatEstCap, Activo)
VALUES (@IdCapQA, @IdUserInst, CURDATE(), CURDATE() + INTERVAL 5 DAY, 1, @IdModalQA, 1, 1); 
SET @IdDatosCapQA = LAST_INSERT_ID();

-- Inscribir Participante (JUAN - @IdUserPart) - Estatus 1 (PROGRAMADO/VIVO)
INSERT INTO `Capacitaciones_Participantes` (Fk_Id_DatosCap, Fk_Id_Usuario, Fk_Id_CatEstPart)
VALUES (@IdDatosCapQA, @IdUserPart, 1);


-- 5.2. INTENTO DE BAJA DE INSTRUCTOR (MARIA)
-- [ESPERADO]: 🔴 ERROR [409]: "...El usuario es INSTRUCTOR en el curso activo..."
CALL SP_CambiarEstatusUsuario(@IdAdminGod, @IdUserInst, 0);


-- 5.3. INTENTO DE BAJA DE PARTICIPANTE (JUAN)
-- [ESPERADO]: 🔴 ERROR [409]: "...El usuario es PARTICIPANTE activo en el curso..."
CALL SP_CambiarEstatusUsuario(@IdAdminGod, @IdUserPart, 0);


/* ====================================================================================================
   FASE 6: GESTIÓN DE ESTATUS Y REACTIVACIÓN (SOFT DELETE)
   Objetivo: Verificar que la baja funcione cuando NO hay candados y que afecte la visibilidad.
   ==================================================================================================== */

-- 6.1. Liberar el Candado (Simular Cancelación de Curso)
-- Esto prueba que si el curso muere (Activo=0), libera a los usuarios.
UPDATE `DatosCapacitaciones` SET Activo = 0 WHERE Id_DatosCap = @IdDatosCapQA;

-- 6.2. Baja Exitosa de Instructor (Maria)
-- [ESPERADO]: Mensaje 'ÉXITO: Usuario ... DESACTIVADO.'
CALL SP_CambiarEstatusUsuario(@IdAdminGod, @IdUserInst, 0);

-- 6.3. Verificar Invisibilidad Operativa
-- [ESPERADO]: Maria NO debe aparecer en la lista de selección.
CALL SP_ListarInstructoresActivos();

-- 6.4. Verificar Visibilidad Histórica
-- [ESPERADO]: Maria debe aparecer marcada como '(BAJA/INACTIVO)'.
CALL SP_ListarTodosInstructores_Historial();

-- 6.5. Baja Exitosa de Participante (Juan)
-- [ESPERADO]: Mensaje 'ÉXITO: Usuario ... DESACTIVADO.'
CALL SP_CambiarEstatusUsuario(@IdAdminGod, @IdUserPart, 0);

-- 6.6. Reactivación de Maria
-- [ESPERADO]: Mensaje 'ÉXITO: Usuario ... REACTIVADO.'
CALL SP_CambiarEstatusUsuario(@IdAdminGod, @IdUserInst, 1);

-- 6.7. Verificar Retorno a la Operación
-- [ESPERADO]: Maria debe aparecer nuevamente en la lista.
CALL SP_ListarInstructoresActivos();

/* ====================================================================================================
   FASE 7: DESTRUCCIÓN TOTAL (LIMPIEZA DE TIERRA QUEMADA)
   Objetivo: Borrar todo el sandbox en orden inverso para validar integridad FK.
   ==================================================================================================== */

-- 7.1. Intento de Borrado Físico de Juan (Tiene historial en Capacitaciones_Participantes)
-- Aunque el curso esté cancelado, el registro histórico existe.
-- [ESPERADO]: 🔴 ERROR [409]: "...Imposible eliminar. Este usuario tiene historial académico..."
CALL SP_EliminarUsuarioDefinitivamente(@IdAdminGod, @IdUserPart);

-- 7.2. Limpieza Forense (Borrar tablas intermedias de capacitación)
SELECT * FROM `Capacitaciones_Participantes`;
DELETE FROM `Capacitaciones_Participantes` WHERE Fk_Id_Usuario = @IdUserPart;

SELECT * FROM `DatosCapacitaciones`;
DELETE FROM `DatosCapacitaciones` WHERE Id_DatosCap = @IdDatosCapQA;

SELECT * FROM `Capacitaciones`;
DELETE FROM `Capacitaciones` WHERE Id_Capacitacion = @IdCapQA;

SELECT * FROM `Cat_Capacitacion`;
DELETE FROM `Cat_Capacitacion` WHERE Id_CatCap = @IdCatCapQA;

SELECT * FROM `Cat_Tipo_Capacitacion`;
DELETE FROM `Cat_Tipo_Capacitacion` WHERE Id_CatTipoCap = @IdTipoCapQA;

SELECT * FROM `Cat_Modalidad_Capacitacion`;
DELETE FROM `Cat_Modalidad_Capacitacion` WHERE Id_CatModalCap = @IdModalQA;

-- 7.3. Eliminación Física de Usuarios (El Cuarteto de Prueba)
-- Ahora sí debe dejar borrar a todos porque están "limpios".
CALL SP_EliminarUsuarioDefinitivamente(@IdAdminGod, @IdUserPart);
CALL SP_EliminarUsuarioDefinitivamente(@IdAdminGod, @IdUserInst);
CALL SP_EliminarUsuarioDefinitivamente(@IdAdminGod, @IdUserCoord);
CALL SP_EliminarUsuarioDefinitivamente(@IdAdminGod, @IdUserAdmin);

-- 7.4. Eliminación de Catálogos Laborales Dummy (Sets A, B y C)
CALL SP_EliminarPuestoFisico(@PueA);
CALL SP_EliminarPuestoFisico(@PueB);
CALL SP_EliminarPuestoFisico(@PueC);

CALL SP_EliminarDepartamentoFisico(@DepA);
CALL SP_EliminarDepartamentoFisico(@DepB);
CALL SP_EliminarDepartamentoFisico(@DepC);

CALL SP_EliminarCentroTrabajoFisico(@CTA);
CALL SP_EliminarCentroTrabajoFisico(@CTB);
CALL SP_EliminarCentroTrabajoFisico(@CTC);

CALL SP_EliminarRegionFisica(@RgnA);
CALL SP_EliminarRegionFisica(@RgnB);
CALL SP_EliminarRegionFisica(@RgnC);

CALL SP_EliminarRegimenFisico(@RegA);
CALL SP_EliminarRegimenFisico(@RegB);
CALL SP_EliminarRegimenFisico(@RegC);

-- 7.5. Eliminación de Jerarquía Organizacional Dummy
DELETE FROM Cat_Gerencias_Activos WHERE Id_CatGeren IN (@GerenA, @GerenB, @GerenC);
DELETE FROM Cat_Subdirecciones WHERE Clave IN ('S_QA_A', 'S_QA_B', 'S_QA_C');
DELETE FROM Cat_Direcciones WHERE Clave IN ('D_QA_A', 'D_QA_B', 'D_QA_C');

-- 7.6. Eliminación de Ubicaciones Dummy
CALL SP_EliminarMunicipio(@MunA);
CALL SP_EliminarMunicipio(@MunB);
CALL SP_EliminarMunicipio(@MunC);

-- Recuperamos IDs físicos de Estado y País para borrarlos
SET @IdEdoA = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_QA_A'); 
CALL SP_EliminarEstadoFisico(@IdEdoA);

SET @IdEdoB = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_QA_B'); 
CALL SP_EliminarEstadoFisico(@IdEdoB);

SET @IdEdoC = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_QA_C'); 
CALL SP_EliminarEstadoFisico(@IdEdoC);

SET @IdPaisA = (SELECT Id_Pais FROM Pais WHERE Codigo = 'P_QA_A'); 
CALL SP_EliminarPaisFisico(@IdPaisA);

SET @IdPaisB = (SELECT Id_Pais FROM Pais WHERE Codigo = 'P_QA_B'); 
CALL SP_EliminarPaisFisico(@IdPaisB);

SET @IdPaisC = (SELECT Id_Pais FROM Pais WHERE Codigo = 'P_QA_C'); 
CALL SP_EliminarPaisFisico(@IdPaisC);

/* ====================================================================================================
   FIN DE LAS PRUEBAS
   Si el script finaliza mostrando el mensaje de abajo, tu sistema ha superado la certificación.
   ==================================================================================================== */
SELECT 'CERTIFICACIÓN DE CALIDAD COMPLETADA: SISTEMA ESTABLE Y LIMPIO.' AS Resultado_Final;