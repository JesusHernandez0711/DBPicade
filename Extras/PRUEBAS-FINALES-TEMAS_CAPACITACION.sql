USE Picade;

/* =================================================================================
   SCRIPT MAESTRO DE VALIDACIÓN (QA) - PICADE
   MÓDULO: TEMAS DE CAPACITACIÓN + KILLSWITCH INTEGRAL
   =================================================================================
   OBJETIVO: Validar CRUD completo, Vistas y Reglas de Integridad (Killswitch).
   ================================================================================= */

-- CONFIGURACIÓN DE ACTOR PRINCIPAL
SET @IdAdminGod = 322; -- Asumiendo que existe el usuario ID 1

/* ---------------------------------------------------------------------------------
   SECCIÓN DE REFERENCIA: DATOS PRE-EXISTENTES (SOLO LECTURA)
   Estos datos YA EXISTEN en la BD. Se dejan aquí comentados por si se requiere
   reconstruir el catálogo en otro entorno.
   --------------------------------------------------------------------------------- */

/*
-- CATÁLOGO: MODALIDAD CAPACITACIÓN
INSERT INTO `Cat_Modalidad_Capacitacion` (Id_CatModalCap, Codigo, Nombre, Descripcion, Activo, created_at, updated_at) VALUES
(1, NULL, 'PRESENCIAL', 'CURSO 100% PRESENCIAL', 1),
(2, NULL, 'VIRTUAL', 'CURSO 100% EN LINEA', 1),
(3, NULL, 'DUAL/SEMIPRESENCIAL', 'PARTE VIRTUAL Y PARTE PRESENCIAL', 1);

-- CATÁLOGO: ESTATUS CAPACITACIÓN
INSERT INTO `Cat_Estatus_Capacitacion` (Id_CatEstCap, Nombre, Descripcion, Es_Final, Activo, created_at, updated_at) VALUES
(1, 'PROGRAMADO', 'CURSO CALENDARIZADO CON SEDE INSTRUCTOR Y LISTA PRELIMINAR', 0, 1, '2026-01-10 13:13:06', '2026-01-10 13:13:06'),
(2, 'POR INICIAR', 'PENDIENTE DE INICIO DETALLES CONFIRMADOS', 0, 1),
(3, 'EN CURSO', 'CURSO ACTUALMENTE EN IMPARTICION', 0, 1),
(4, 'FINALIZADO', 'CURSO IMPARTIDO EN SU TOTALIDAD', 1, 1),
(5, 'EN EVALUACION', 'EN PROCESO DE EVALUACION Y EVIDENCIAS', 0, 1),
(6, 'ACREDITADO', 'PARTICIPANTES HAN CUMPLIDO REQUISITOS MINIMOS', 1, 1),
(7, 'NO ACREDITADO', 'PARTICIPANTES NO CUMPLEN REQUISITOS MINIMOS', 1, 1),
(8, 'CANCELADO', 'CURSO CANCELADO ANTES DE INICIAR', 1, 1),
(9, 'REPROGRAMADO', 'CURSO REPROGRAMADO (FECHAS/SEDE/MODALIDAD)', 0, 1),
(10, 'CERRADO/ARCHIVADO', 'CURSO CON EXPEDIENTE COMPLETO Y ARCHIVADO', 1, 1);
*/

-- DEFINICIÓN DE VARIABLES BASADAS EN TUS DATOS EXISTENTES
SET @IdModalPresencial = 1; -- PRESENCIAL
SET @IdEstProgramado = 1;   -- PROGRAMADO (Bloqueante)
SET @IdEstEnCurso = 3;      -- EN CURSO (Bloqueante)
SET @IdEstFinalizado = 4;   -- FINALIZADO (No Bloqueante)

/* =================================================================================
   FASE 0: CONSTRUCCIÓN DE INFRAESTRUCTURA (SANDBOX)
   ================================================================================= */

-- 0.1. GEOGRAFÍA
CALL SP_RegistrarUbicaciones('M_QA_TEM', 'MUNICIPIO TEMAS QA', 'E_QA_TEM', 'ESTADO TEMAS QA', 'P_QA_TEM', 'PAIS TEMAS QA');
SET @IdMunQA = (SELECT Id_Municipio FROM Municipio WHERE Codigo = 'M_QA_TEM');

-- 0.2. ORGANIZACIÓN
CALL SP_RegistrarOrganizacion('G_QA_TEM', 'GERENCIA TEMAS QA', 'S_QA_TEM', 'SUBDIRECCION TEMAS QA', 'D_QA_TEM', 'DIRECCION TEMAS QA');
SET @IdGerenQA = (SELECT Id_CatGeren FROM Cat_Gerencias_Activos WHERE Clave = 'G_QA_TEM');

-- 0.3. INFRAESTRUCTURA FÍSICA
CALL SP_RegistrarSede('CASES-QA-TEM', 'SEDE CAPACITACION QA', 'Calle Pruebas 123', @IdMunQA, 50, 2, 1, 0, 0, 0, 0);
SET @IdSedeQA = (SELECT Id_CatCases_Sedes FROM Cat_Cases_Sedes WHERE Codigo = 'CASES-QA-TEM');

-- 0.4. CATÁLOGOS LABORALES
CALL SP_RegistrarRegimen('REG-QA', 'REGIMEN QA', 'TEST');
SET @IdRegQA = (SELECT Id_CatRegimen FROM Cat_Regimenes_Trabajo WHERE Codigo = 'REG-QA');

CALL SP_RegistrarPuesto('PUE-INST', 'INSTRUCTOR DE CAMPO', 'TEST');
SET @IdPuestoQA = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo WHERE Codigo = 'PUE-INST');

CALL SP_RegistrarRegion('RGN-QA', 'REGION QA', 'TEST');
SET @IdRegionQA = (SELECT Id_CatRegion FROM Cat_Regiones_Trabajo WHERE Codigo = 'RGN-QA');

CALL SP_RegistrarDepartamento('DEP-CAP', 'CAPACITACION', 'OFICINA', @IdMunQA);
SET @IdDepQA = (SELECT Id_CatDep FROM Cat_Departamentos WHERE Codigo = 'DEP-CAP');

-- 0.5. RECURSO HUMANO (Instructor)
CALL SP_RegistrarUsuarioPorAdmin(@IdAdminGod, 'F-INST-QA', NULL, 'PEDRO', 'INSTRUCTOR', 'QA', '1980-01-01', '2010-01-01', 'inst_temas@qa.com', '123', 3, @IdRegQA, @IdPuestoQA, NULL, @IdDepQA, @IdRegionQA, @IdGerenQA, 'N1', 'C1');
SET @IdInstructorQA = (SELECT Id_Usuario FROM Usuarios WHERE Ficha = 'F-INST-QA');

-- 0.6. CATÁLOGOS ACADÉMICOS (Tipos de Instrucción)
CALL SP_RegistrarTipoInstruccion('TÉCNICO OPERATIVO QA', 'Cursos de operación en campo');
SET @IdTipoTecnico = (SELECT Id_CatTipoInstCap FROM Cat_Tipos_Instruccion_Cap WHERE Nombre = 'TÉCNICO OPERATIVO QA');

CALL SP_RegistrarTipoInstruccion('SEGURIDAD SSPA QA', 'Normatividad de seguridad');
SET @IdTipoSeguridad = (SELECT Id_CatTipoInstCap FROM Cat_Tipos_Instruccion_Cap WHERE Nombre = 'SEGURIDAD SSPA QA');

/* =================================================================================
   FASE 1: REGISTRO DE TEMAS (CREATE & SEEDING)
   Objetivo: Crear datos maestros para pruebas de integridad, borrado y reportes.
   ================================================================================= */

-- ---------------------------------------------------------------------------------
-- A. CASOS DE ÉXITO (Happy Path) - Mínimo 3 registros para validaciones cruzadas
-- ---------------------------------------------------------------------------------

-- 1.1. Registrar Tema "Víctima" (CASO: Integridad Referencial)
-- Este tema se usará para intentar borrarlo cuando ya tenga cursos ligados (debe fallar el delete físico).
CALL SP_RegistrarTemaCapacitacion('TEMA-KILL-01', 'SEGURIDAD BASICA SSPA', 'Tema crítico con cursos activos para prueba de candado', 20, @IdTipoTecnico);
SET @IdTemaVictima = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'TEMA-KILL-01');

-- 1.2. Registrar Tema "Limpio" (CASO: Borrado Exitoso)
-- Este tema NO tendrá cursos hijos. Se usará para probar que el DELETE físico funciona en datos aislados.
CALL SP_RegistrarTemaCapacitacion('TEMA-CLEAN-02', 'INTRODUCCION A LA CALIDAD', 'Tema huerfano para prueba de borrado limpio', 8, @IdTipoTecnico);
SET @IdTemaLimpio = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'TEMA-CLEAN-02');

-- 1.3. Registrar Tema "Estándar" (CASO: Modificación y Auditoría)
-- Este tema se usará para probar el UPDATE y verificar que cambie el timestamp de 'updated_to'.
CALL SP_RegistrarTemaCapacitacion('TEMA-UPD-03', 'OPERACION DE EQUIPOS CRITICOS', 'Tema destinado a sufrir modificaciones de nombre y horas', 40, @IdTipoTecnico);
SET @IdTemaUpdate = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'TEMA-UPD-03');

-- 1.4. Registrar Tema "Reportes" (CASO: Agrupación de Datos)
-- Este tema servirá para asignarle múltiples instructores y ver cómo se comporta en consultas complejas.
CALL SP_RegistrarTemaCapacitacion('TEMA-REP-04', 'LIDERAZGO Y GESTION', 'Tema soft-skill para validación de reportes mixtos', 16, @IdTipoTecnico);
SET @IdTemaReporte = (SELECT Id_Cat_TemasCap FROM Cat_Temas_Capacitacion WHERE Codigo = 'TEMA-REP-04');

-- ---------------------------------------------------------------------------------
-- B. PRUEBAS DE ERROR (Negative Testing)
-- ---------------------------------------------------------------------------------

-- 1.5. Prueba de Error: Campos Obligatorios (Debe retornar error de validación)
-- Se envía NULL en el código para activar la validación del SP.
CALL SP_RegistrarTemaCapacitacion(NULL, 'SIN CODIGO', 'Desc', 0, @IdTipoTecnico); 

-- 1.6. Prueba de Error: Duplicidad (Debe retornar error de llave única)
-- Se intenta registrar 'TEMA-KILL-01' nuevamente.
CALL SP_RegistrarTemaCapacitacion('TEMA-KILL-01', 'NOMBRE DUPLICADO', 'Intento de duplicado', 20, @IdTipoTecnico); 

-- ---------------------------------------------------------------------------------
-- C. VERIFICACIÓN FINAL
-- ---------------------------------------------------------------------------------
-- SELECT * FROM Cat_Temas_Capacitacion ORDER BY Id_Cat_TemasCap DESC LIMIT 5;

/* =================================================================================
   FASE 2: LECTURA Y VISTAS (READ) - VERIFICACIÓN VISUAL
   ================================================================================= */
SELECT '--- FASE 2: LECTURA DE CATÁLOGOS ---' AS LOG;

-- 2.1. Listado Completo para Administrador (Muestra Activos e Inactivos)
CALL SP_ListarTemasAdmin();

-- 2.2. Listado Filtrado para Dropdowns (Solo Activos)
CALL SP_ListarTemasActivos();

-- 2.3. Consulta de Detalle Específico (Para precargar formularios)
CALL SP_ConsultarTemaCapacitacionEspecifico(@IdTemaVictima);

/* =================================================================================
   FASE 3: EDICIÓN E INTEGRIDAD (UPDATE)
   Objetivo: Validar cada cláusula IF del SP_EditarTemaCapacitacion
   ================================================================================= */
-- SELECT '--- FASE 3: EDICIÓN ---' AS LOG;

-- ---------------------------------------------------------------------------------
-- A. PRUEBAS DE VALIDACIÓN DE ENTRADA (Input Validation)
-- ---------------------------------------------------------------------------------

-- 3.1. ID Inválido (IF _Id_Tema <= 0)
-- Esperado: ERROR DE SISTEMA [400]: Identificador de Tema inválido.
CALL SP_EditarTemaCapacitacion(0, 'CODE', 'NAME', 'Desc', 10, @IdTipoTecnico);

-- 3.2. Código Nulo (IF _Codigo IS NULL)
-- Esperado: ERROR DE VALIDACIÓN [400]: El CÓDIGO es obligatorio.
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, NULL, 'NAME', 'Desc', 10, @IdTipoTecnico);

-- 3.3. Nombre Nulo (IF _Nombre IS NULL)
-- Esperado: ERROR DE VALIDACIÓN [400]: El NOMBRE es obligatorio.
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, 'TEMA-KILL-01', NULL, 'Desc', 10, @IdTipoTecnico);

-- 3.4. Duración Inválida (IF _Duracion_Horas <= 0)
-- Esperado: ERROR DE VALIDACIÓN [400]: La DURACIÓN debe ser mayor a 0 horas.
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, 'TEMA-KILL-01', 'NAME', 'Desc', 0, @IdTipoTecnico);

-- 3.5. Tipo Instrucción Inválido (IF _Id_TipoInst <= 0)
-- Esperado: ERROR DE VALIDACIÓN [400]: Debe seleccionar un TIPO DE INSTRUCCIÓN válido.
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, 'TEMA-KILL-01', 'NAME', 'Desc', 10, 0);

-- ---------------------------------------------------------------------------------
-- B. PRUEBAS DE LÓGICA DE NEGOCIO E INTEGRIDAD
-- ---------------------------------------------------------------------------------

-- 3.6. Edición de Registro Inexistente (IF v_Cod_Act IS NULL)
-- Simulamos que alguien intenta editar un ID que no existe (o fue borrado por otro).
-- Esperado: ERROR CRÍTICO [404]: El Tema que intenta editar ya no existe.
CALL SP_EditarTemaCapacitacion(99999, 'FANTASMA', 'Fantasma', 'Desc', 10, @IdTipoTecnico);

-- 3.7. Integridad Referencial - Padre No Existe (IF v_Padre_Activo IS NULL)
-- Intentamos asignar un Tipo de Instrucción que no existe en la base de datos (ej. ID 999).
-- Esperado: ERROR DE INTEGRIDAD [404]: El nuevo Tipo de Instrucción seleccionado no existe.
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, 'TEMA-KILL-01', 'Test FK', 'Desc', 10, 999);

-- 3.8. Conflicto de Código Único (IF v_Id_Conflicto IS NOT NULL)
-- Intentamos ponerle al "Tema Limpio" el código del "Tema Víctima".
-- Esperado: CONFLICTO DE DATOS [409]: El CÓDIGO ingresado ya pertenece a otro Tema.
CALL SP_EditarTemaCapacitacion(@IdTemaLimpio, 'TEMA-KILL-01', 'INTENTO ROBO', 'Desc', 10, @IdTipoTecnico);

-- ---------------------------------------------------------------------------------
-- C. CASOS DE COMPORTAMIENTO ESPERADO (Happy Path & Idempotency)
-- ---------------------------------------------------------------------------------

-- 3.9. Detección de "Sin Cambios" (LEAVE THIS_PROC)
-- Enviamos exactamente los mismos datos que ya tiene el registro.
-- Esperado: AVISO: No se detectaron cambios en la información. (Accion: SIN_CAMBIOS)
-- Nota: Asegúrate de usar los valores actuales de @IdTemaVictima.
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, 'TEMA-KILL-01', 'SEGURIDAD BASICA SSPA', 'Tema crítico con cursos activos para prueba de candado', 20, @IdTipoTecnico);

-- 3.10. Edición Exitosa (Happy Path)
-- Cambiamos Nombre, Descripción y Horas del "Tema Víctima".
-- Esperado: Mensaje de éxito estándar.
CALL SP_EditarTemaCapacitacion(@IdTemaVictima, 'TEMA-KILL-01', 'SEGURIDAD BASICA SSPA (V2)', 'Actualizado tras revisión anual', 24, @IdTipoTecnico);

-- ---------------------------------------------------------------------------------
-- D. VERIFICACIÓN POST-TEST
-- ---------------------------------------------------------------------------------
-- Validamos que el cambio del paso 3.10 se reflejó y que updated_to cambió.
/*SELECT Id_Cat_TemasCap, Codigo, Nombre, Duracion_Horas, created_to, updated_to 
FROM Cat_Temas_Capacitacion 
WHERE Id_Cat_TemasCap = @IdTemaVictima;*/

/* =================================================================================
   FASE 4: CAMBIO DE ESTATUS, KILLSWITCH Y REGLAS DE JERARQUÍA
   Objetivo: Validar SP_CambiarEstatusTemaCapacitacion y sus bloqueos lógicos.
   ================================================================================= */
-- SELECT '--- FASE 4: KILLSWITCH Y REGLAS DE NEGOCIO ---' AS LOG;

-- ---------------------------------------------------------------------------------
-- A. VALIDACIONES DE ENTRADA (Input Validation)
-- ---------------------------------------------------------------------------------

-- 4.1. ID Inválido (IF _Id_Tema <= 0)
-- Esperado: ERROR DE SISTEMA [400]: ID de Tema inválido.
CALL SP_CambiarEstatusTemaCapacitacion(0, 0);

-- 4.2. Estatus Inválido (IF _Nuevo_Estatus NOT IN (0, 1))
-- Esperado: ERROR DE SISTEMA [400]: El estatus solo puede ser 0 o 1.
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 5);

-- 4.3. Tema Inexistente (IF v_Activo_Actual IS NULL)
-- Esperado: ERROR DE NEGOCIO [404]: El Tema solicitado no existe.
CALL SP_CambiarEstatusTemaCapacitacion(99999, 0);

-- ---------------------------------------------------------------------------------
-- B. PRUEBA DEL "KILLSWITCH" (Conflictos Operativos)
-- ---------------------------------------------------------------------------------
-- Configuración del Escenario: Creamos un curso ACTIVO ligado al "Tema Víctima".

-- 4.4. Crear Cabecera de Capacitación
INSERT INTO `Capacitaciones` (Numero_Capacitacion, Fk_Id_CatGeren, Fk_Id_Cat_TemasCap, Asistentes_Programados, Activo, created_at, updated_at) 
VALUES ('FOLIO-KILL-001', @IdGerenQA, @IdTemaVictima, 15, 1, NOW(), NOW());
SET @IdCapKill = LAST_INSERT_ID();

-- 4.5. Asignar Estatus "EN CURSO" (Bloqueante)
-- Usamos un estatus que el sistema considera "vivo" (ej. ID 3).
INSERT INTO `DatosCapacitaciones` (Fk_Id_Capacitacion, Fk_Id_Instructor, Fecha_Inicio, Fecha_Fin, Fk_Id_CatCases_Sedes, Fk_Id_CatModalCap, Fk_Id_CatEstCap, Activo, Comentarios, created_at, updated_at) 
VALUES (@IdCapKill, @IdInstructorQA, NOW(), DATE_ADD(NOW(), INTERVAL 5 DAY), @IdSedeQA, @IdModalPresencial, @IdEstEnCurso, 1, 'Prueba Killswitch', NOW(), NOW()); 

-- 4.6. INTENTO DE DESACTIVACIÓN ILEGAL (IF v_Curso_Conflictivo IS NOT NULL)
-- Intentamos apagar el tema mientras el curso de arriba sigue activo.
-- Esperado: CONFLICTO OPERATIVO [409]: No se puede desactivar... Está asignado a la capacitación activa...
SELECT 'PRUEBA 4.6: Killswitch Activado (Debe Fallar)' AS Test_Step;
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 0);

-- ---------------------------------------------------------------------------------
-- C. RESOLUCIÓN DEL CONFLICTO Y DESACTIVACIÓN (Baja Lógica)
-- ---------------------------------------------------------------------------------

-- 4.7. Evolución del Curso (Liberación del Candado)
-- Cambiamos el estatus del curso a "FINALIZADO" (ID histórico, ya no bloquea).
UPDATE `DatosCapacitaciones` 
SET Fk_Id_CatEstCap = @IdEstFinalizado, Comentarios = 'Curso finalizado, liberando tema', updated_at = NOW()
WHERE Fk_Id_Capacitacion = @IdCapKill AND Activo = 1;

-- 4.8. DESACTIVACIÓN EXITOSA (Happy Path)
-- Ahora que no hay cursos activos, el sistema debe permitir la baja.
-- Esperado: Mensaje de éxito "DESACTIVADO".
SELECT 'PRUEBA 4.8: Desactivación Legal (Debe Funcionar)' AS Test_Step;
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 0);

-- Verificación: El tema debe tener Activo = 0
SELECT Id_Cat_TemasCap, Codigo, Activo FROM Cat_Temas_Capacitacion WHERE Id_Cat_TemasCap = @IdTemaVictima;

-- ---------------------------------------------------------------------------------
-- D. VALIDACIÓN DE JERARQUÍA (Padre Inactivo)
-- ---------------------------------------------------------------------------------
-- Escenario: Intentar reactivar el tema cuando su "Tipo de Instrucción" (Padre) está apagado.

-- 4.9. Simular Padre Inactivo
-- Obtenemos el ID del padre (Tipo Tecnico) y lo desactivamos temporalmente "a la fuerza".
UPDATE Cat_Tipos_Instructores SET Activo = 0 WHERE Id_Cat_Tipos_Instructores = @IdTipoTecnico;

-- 4.10. Intento de Reactivación Huérfana (IF v_Tipo_Activo = 0)
-- Intentamos encender el tema @IdTemaVictima (que está en 0 por el paso 4.8).
-- Esperado: ERROR DE INTEGRIDAD / ERROR_JERARQUIA: No se puede activar... Reactive la categoría primero.
SELECT 'PRUEBA 4.10: Validación de Jerarquía (Debe Fallar)' AS Test_Step;
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 1);

-- 4.11. Restaurar Padre
-- Volvemos a activar el padre para poder continuar.
UPDATE Cat_Tipos_Instructores SET Activo = 1 WHERE Id_Cat_Tipos_Instructores = @IdTipoTecnico;

-- ---------------------------------------------------------------------------------
-- E. REACTIVACIÓN FINAL
-- ---------------------------------------------------------------------------------

-- 4.12. Reactivación Exitosa
-- Dejamos el tema vivo para las pruebas de borrado físico que siguen en la Fase 5 (o para dejar la BD limpia).
CALL SP_CambiarEstatusTemaCapacitacion(@IdTemaVictima, 1);

/* =================================================================================
   FASE 5: ELIMINACIÓN FÍSICA (HARD DELETE)
   Objetivo: Probar validaciones de entrada, existencia y protección de integridad.
   ================================================================================= */
SELECT '--- FASE 5: ELIMINACIÓN FÍSICA ---' AS LOG;

-- ---------------------------------------------------------------------------------
-- A. VALIDACIONES DE ENTRADA (Input Validation)
-- ---------------------------------------------------------------------------------

-- 5.1. ID Inválido (IF _Id_Tema <= 0)
-- Enviamos un 0 para activar la primera barrera.
-- Esperado: ERROR DE SISTEMA [400]: El Identificador del Tema es inválido.
CALL SP_EliminarTemaCapacitacionFisico(0);

-- ---------------------------------------------------------------------------------
-- B. VALIDACIÓN DE EXISTENCIA
-- ---------------------------------------------------------------------------------

-- 5.2. Tema Inexistente (IF NOT EXISTS...)
-- Intentamos borrar un ID que no está en la tabla (ej. 99999).
-- Esperado: ERROR DE NEGOCIO [404]: El Tema de Capacitación que intenta eliminar no existe.
CALL SP_EliminarTemaCapacitacionFisico(99999);

-- ---------------------------------------------------------------------------------
-- C. PRUEBA DE BLOQUEO DE NEGOCIO (INTEGRIDAD REFERENCIAL LÓGICA)
-- ---------------------------------------------------------------------------------

-- 5.3. Intento de Borrado con Historial (IF v_Dependencias IS NOT NULL)
-- Usamos @IdTemaVictima. En la Fase 4 le creamos la capacitación 'FOLIO-KILL-001'.
-- Aunque el curso esté "Finalizado" (histórico), el tema NO debe poder borrarse físicamente.
-- Esperado: BLOQUEO DE NEGOCIO [409]: No es posible eliminar este Tema porque existen CAPACITACIONES...
SELECT 'PRUEBA 5.3: Eliminación de Tema con Historial (Debe Fallar)' AS Test_Step;
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaVictima);

/* NOTA SOBRE EL HANDLER 1451:
   Esta prueba 5.3 validará primero tu bloque lógico (Error 409). 
   El HANDLER 1451 es tu "paracaídas". Solo se dispararía si por alguna razón tu SELECT de validación 
   falla pero la base de datos detecta la llave foránea al momento del DELETE real. 
   Al funcionar el 409, implícitamente confirmamos que la integridad está a salvo. */

-- ---------------------------------------------------------------------------------
-- D. CASO DE ÉXITO (HAPPY PATH)
-- ---------------------------------------------------------------------------------

-- 5.4. Borrado Físico de Tema Limpio
-- Usamos @IdTemaLimpio (creado en Fase 1). Nunca le asignamos cursos.
-- Al no tener dependencias, debe pasar todas las validaciones y llegar al DELETE.
-- Esperado: Mensaje de éxito "ELIMINADA".
SELECT 'PRUEBA 5.4: Eliminación de Tema Virgen (Debe Funcionar)' AS Test_Step;
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaLimpio);

-- ---------------------------------------------------------------------------------
-- E. VERIFICACIÓN FINAL
-- ---------------------------------------------------------------------------------
-- Comprobamos que el "Limpio" desapareció y el "Víctima" sigue vivo (aunque desactivado).
/*SELECT Id_Cat_TemasCap, Codigo, Nombre, Activo 
FROM Cat_Temas_Capacitacion 
WHERE Id_Cat_TemasCap IN (@IdTemaVictima, @IdTemaLimpio);*/

/* =================================================================================
   FASE 6: LIMPIEZA TOTAL (TEARDOWN) - REINICIO DE ENTORNO
   Objetivo: Eliminar CADA registro creado durante las pruebas usando los SPs Físicos.
   Orden: De Hijos a Padres (Bottom-Up) para respetar la Integridad Referencial.
   ================================================================================= */
-- SELECT '--- FASE 6: LIMPIEZA DE ENTORNO (TEARDOWN) ---' AS LOG;

-- ---------------------------------------------------------------------------------
-- 6.1. LIMPIEZA TRANSACCIONAL (Nivel más bajo)
-- ---------------------------------------------------------------------------------
-- Eliminamos los datos de la capacitación de prueba si aún existen
DELETE FROM `DatosCapacitaciones` WHERE Fk_Id_Capacitacion = @IdCapKill;
DELETE FROM `Capacitaciones` WHERE Id_Capacitacion = @IdCapKill;

-- ---------------------------------------------------------------------------------
-- 6.2. LIMPIEZA DE TEMAS (Hijos de Tipos de Instrucción)
-- ---------------------------------------------------------------------------------
-- Borramos los temas que quedaron vivos (Victima, Update, Reporte). 
-- Nota: 'Tema Limpio' ya fue borrado en la Fase 5.
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaVictima); 
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaUpdate);
CALL SP_EliminarTemaCapacitacionFisico(@IdTemaReporte);

-- ---------------------------------------------------------------------------------
-- 6.3. LIMPIEZA DE CATÁLOGOS ACADÉMICOS (Padres de Temas)
-- ---------------------------------------------------------------------------------
CALL SP_EliminarTipoInstruccionFisico(@IdTipoTecnico);
CALL SP_EliminarTipoInstruccionFisico(@IdTipoSeguridad);

-- ---------------------------------------------------------------------------------
-- 6.4. LIMPIEZA DE RECURSOS HUMANOS (Usuarios y Dependencias)
-- ---------------------------------------------------------------------------------
-- Eliminamos al Instructor (Esto borra Usuario e Info_Personal en cascada controlada)
CALL SP_EliminarUsuarioDefinitivamente(@IdAdminGod, @IdInstructorQA);

-- Ahora que no hay empleados, podemos borrar los catálogos laborales asociados
CALL SP_EliminarDepartamentoFisico(@IdDepQA);
CALL SP_EliminarPuestoFisico(@IdPuestoQA);
CALL SP_EliminarRegimenFisico(@IdRegQA);
CALL SP_EliminarRegionFisica(@IdRegionQA);

-- ---------------------------------------------------------------------------------
-- 6.5. LIMPIEZA DE INFRAESTRUCTURA FÍSICA
-- ---------------------------------------------------------------------------------
CALL SP_EliminarSedeFisica(@IdSedeQA); 

-- ---------------------------------------------------------------------------------
-- 6.6. LIMPIEZA DE ORGANIZACIÓN (Jerarquía: Gerencia -> Subdirección -> Dirección)
-- ---------------------------------------------------------------------------------
-- 1. Eliminamos Gerencia (Variable ya existente)
CALL SP_EliminarGerenciaFisica(@IdGerenQA);

-- 2. Eliminamos Subdirección (Recuperamos ID por Clave antes de borrar)
SET @IdSubQA = (SELECT Id_CatSubDirec FROM Cat_Subdirecciones WHERE Clave = 'S_QA_TEM');
CALL SP_EliminarSubdireccionFisica(@IdSubQA);

-- 3. Eliminamos Dirección (Recuperamos ID por Clave antes de borrar)
SET @IdDirQA = (SELECT Id_CatDirecc FROM Cat_Direcciones WHERE Clave = 'D_QA_TEM');
CALL SP_EliminarDireccionFisica(@IdDirQA);

-- ---------------------------------------------------------------------------------
-- 6.7. LIMPIEZA DE GEOGRAFÍA (Jerarquía: Municipio -> Estado -> País)
-- ---------------------------------------------------------------------------------
-- 1. Eliminamos Municipio (Variable ya existente)
CALL SP_EliminarMunicipio(@IdMunQA);

-- 2. Eliminamos Estado (Recuperamos ID por Código antes de borrar)
SET @IdEdoQA = (SELECT Id_Estado FROM Estado WHERE Codigo = 'E_QA_TEM');
CALL SP_EliminarEstadoFisico(@IdEdoQA);

-- 3. Eliminamos País (Recuperamos ID por Código antes de borrar)
SET @IdPaisQA = (SELECT Id_Pais FROM Pais WHERE Codigo = 'P_QA_TEM');
CALL SP_EliminarPaisFisico(@IdPaisQA);

-- ---------------------------------------------------------------------------------
-- CONFIRMACIÓN FINAL
-- ---------------------------------------------------------------------------------
-- SELECT 'PRUEBAS QA FINALIZADAS Y ENTORNO RESTAURADO AL 100%' AS Estatus_Final;