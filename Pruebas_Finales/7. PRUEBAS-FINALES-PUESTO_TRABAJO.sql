/* =================================================================================
   SCRIPT DE VALIDACIÓN (QA) - MÓDULO PUESTOS DE TRABAJO
   =================================================================================
   OBJETIVO:
   Validar la robustez del módulo `Cat_Puestos_Trabajo`.
   
   ALCANCE DE PRUEBAS:
   1. Registro: Validación de obligatoriedad, identidad dual y autosanación.
   2. Lectura: Vistas operativas vs administrativas.
   3. Edición: Bloqueo de duplicados y detección de "Sin Cambios".
   4. Estatus: Bloqueo de desactivación si hay empleados activos.
   5. Eliminación: Bloqueo de borrado físico si hay historial laboral.
   ================================================================================= */

USE Picade;

/* ---------------------------------------------------------------------------------
   FASE 0: LIMPIEZA PREVIA (Opcional, para reiniciar pruebas)
   --------------------------------------------------------------------------------- */
-- DELETE FROM Cat_Puestos_Trabajo WHERE Codigo LIKE 'PUE-QA%';

/* =================================================================================
   FASE 1: REGISTRO Y REGLAS DE UNICIDAD (HAPPY PATH & DIRTY DATA)
   Objetivo: Verificar creación, sanitización y manejo de duplicados.
   ================================================================================= */

-- 1.1. Registro Exitoso (Happy Path)
-- [ESPERADO]: Mensaje 'Puesto registrado correctamente', Accion 'CREADA'.
CALL SP_RegistrarPuesto('PUE-QA-01', 'PUESTO ALPHA DE PRUEBA', 'DESCRIPCION INICIAL');

-- Guardamos ID para pruebas posteriores
SET @IdPuesto1 = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo WHERE Codigo = 'PUE-QA-01');

-- 1.2. Prueba de "Todo Obligatorio" (Intentar registrar NULLs)
-- [ESPERADO]: 🔴 ERROR [400]: "ERROR DE VALIDACIÓN: El CÓDIGO del Puesto es obligatorio."
CALL SP_RegistrarPuesto(NULL, 'NOMBRE SIN CODIGO', 'DESC');

-- 1.3. Registro del Segundo Dato (Para pruebas cruzadas)
-- [ESPERADO]: Accion 'CREADA'.
CALL SP_RegistrarPuesto('PUE-QA-02', 'PUESTO BETA DE PRUEBA', 'DESCRIPCION BETA');
SET @IdPuesto2 = (SELECT Id_CatPuesto FROM Cat_Puestos_Trabajo WHERE Codigo = 'PUE-QA-02');

-- 1.4. Prueba de Idempotencia por CÓDIGO (Re-enviar lo mismo del 1.1)
-- [ESPERADO]: Mensaje '...ya se encuentra registrado...', Accion 'REUSADA'.
CALL SP_RegistrarPuesto('PUE-QA-01', 'PUESTO ALPHA DE PRUEBA', 'OTRA DESC');

-- 1.5. Conflicto de Identidad Cruzada (Mismo Código, diferente Nombre)
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS: El CÓDIGO ingresado ya existe..."
CALL SP_RegistrarPuesto('PUE-QA-01', 'NOMBRE IMPOSTOR', 'DESC');

-- 1.6. Conflicto de Identidad Cruzada (Mismo Nombre, diferente Código)
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS: El NOMBRE ingresado ya existe..."
CALL SP_RegistrarPuesto('PUE-QA-99', 'PUESTO ALPHA DE PRUEBA', 'DESC');


/* =================================================================================
   FASE 2: LECTURA Y VISTAS
   Objetivo: Verificar que la UI reciba los datos correctos y limpios.
   ================================================================================= */

-- 2.1. Listado Admin (Vista Completa - Grid)
-- [ESPERADO]: Deben salir los 2 registros creados. Verificar columna 'Estatus_Puesto'.
CALL SP_ListarPuestosAdmin();

-- 2.2. Listado Activos (Dropdown Operativo)
-- [ESPERADO]: Solo ID, Código y Nombre. Deben salir ambos.
CALL SP_ListarPuestosActivos();

-- 2.3. Consulta Específica (Para Edición - Raw Data)
-- [ESPERADO]: Datos crudos. Verificar fechas created_at/updated_at.
CALL SP_ConsultarPuestoEspecifico(@IdPuesto1);


/* =================================================================================
   FASE 3: EDICIÓN E INTEGRIDAD
   Objetivo: Verificar validaciones al modificar datos y bloqueos.
   ================================================================================= */

-- 3.1. Prueba "Sin Cambios" (Idempotencia en Update)
-- [ESPERADO]: Mensaje 'No se detectaron cambios...', Accion 'SIN_CAMBIOS'.
CALL SP_EditarPuesto(@IdPuesto1, 'PUE-QA-01', 'PUESTO ALPHA DE PRUEBA', 'DESCRIPCION INICIAL');

-- 3.2. Prueba de Duplicidad Global (Robar código de otro)
-- Intentamos ponerle al Puesto 2 el código del Puesto 1.
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS: El CÓDIGO ya pertenece a otro Puesto."
CALL SP_EditarPuesto(@IdPuesto2, 'PUE-QA-01', 'NOMBRE X', 'DESC');

-- 3.3. Prueba de Duplicidad Global (Robar nombre de otro)
-- Intentamos ponerle al Puesto 2 el nombre del Puesto 1.
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE DATOS: El NOMBRE ya pertenece a otro Puesto."
CALL SP_EditarPuesto(@IdPuesto2, 'COD-X', 'PUESTO ALPHA DE PRUEBA', 'DESC');

-- 3.4. Edición Correcta (Evolución de datos)
-- Cambiamos nombre y descripción del Puesto 2.
-- [ESPERADO]: Mensaje 'Puesto actualizado correctamente.', Accion 'ACTUALIZADA'.
CALL SP_EditarPuesto(@IdPuesto2, 'PUE-QA-02', 'PUESTO BETA EVOLUCIONADO', 'NUEVA DESCRIPCION');


/* =================================================================================
   FASE 4: ESTATUS Y CANDADOS DE INTEGRIDAD (SIMULACIÓN DE PERSONAL)
   Objetivo: Verificar que no se pueda desactivar si hay uso real.
   ================================================================================= */

-- 4.1. Desactivar Puesto 1 (Baja Lógica - Sin empleados aún)
-- [ESPERADO]: Mensaje '...Puesto ha sido DESACTIVADO...'.
CALL SP_CambiarEstatusPuesto(@IdPuesto1, 0);

-- 4.2. Verificar Listado Operativo
-- [ESPERADO]: El PUE-QA-01 NO debe aparecer en el dropdown (SP_ListarPuestosActivos).
CALL SP_ListarPuestosActivos();

-- 4.3. Reactivar Puesto 1 (Para preparar la siguiente prueba)
-- [ESPERADO]: Mensaje '...Puesto ha sido REACTIVADO...'.
CALL SP_CambiarEstatusPuesto(@IdPuesto1, 1);

/* ---------------------------------------------------------------------------------
   [SIMULACIÓN DE CANDADO DE NEGOCIO]
   Simulamos la asignación de este puesto a un empleado.
   --------------------------------------------------------------------------------- */

-- A. Insertar Empleado Dummy vinculado al Puesto 1 (@IdPuesto1)
-- IMPORTANTE: Se usan datos mínimos requeridos por la tabla Info_Personal
INSERT INTO `Info_Personal` (Nombre, Apellido_Paterno, Apellido_Materno, Fk_Id_CatPuesto, Activo) 
VALUES ('EMPLEADO_TEST_PUESTO', 'QA', 'LAB', @IdPuesto1, 1);

SET @IdEmpleadoDummy = LAST_INSERT_ID();

-- 4.4. Intentar Desactivar Puesto 1 con Empleado Activo
-- [ESPERADO]: 🔴 ERROR [409]: "CONFLICTO DE INTEGRIDAD... Existen EMPLEADOS ACTIVOS..."
CALL SP_CambiarEstatusPuesto(@IdPuesto1, 0);

-- B. Liberar Candado (Simular que damos de baja al empleado)
UPDATE `Info_Personal` SET Activo = 0 WHERE Id_InfoPersonal = @IdEmpleadoDummy;

-- 4.5. Intentar Desactivar de nuevo (Ahora limpio de activos)
-- [ESPERADO]: ÉXITO.
CALL SP_CambiarEstatusPuesto(@IdPuesto1, 0);


/* =================================================================================
   FASE 5: ELIMINACIÓN FÍSICA (HARD DELETE)
   Objetivo: Limpieza final y prueba de los 3 Anillos de Seguridad.
   ================================================================================= */

-- 5.1. Intentar Borrar Puesto Inexistente
-- [ESPERADO]: 🔴 ERROR [404]: "El Puesto que intenta eliminar no existe..."
CALL SP_EliminarPuestoFisico(999999);

/* ---------------------------------------------------------------------------------
   [PRUEBA DE CANDADO HISTÓRICO]
   El empleado dummy (@IdEmpleadoDummy) está Inactivo (Activo=0), pero EXISTE en la BD.
   Por lo tanto, NO DEBE DEJAR BORRAR FISICAMENTE el puesto, para no romper el historial.
   --------------------------------------------------------------------------------- */

-- 5.2. Intentar Borrar Puesto 1 (Tiene historial inactivo)
-- [ESPERADO]: 🔴 ERROR [409]: "...Existen expedientes de PERSONAL (Activos o Históricos)..."
CALL SP_EliminarPuestoFisico(@IdPuesto1);

-- C. Limpieza TOTAL del Histórico para permitir borrado (Solo para efectos de prueba)
DELETE FROM `Info_Personal` WHERE Id_InfoPersonal = @IdEmpleadoDummy;

-- 5.3. Eliminación Física Exitosa - Puesto 1
-- [ESPERADO]: 'ÉXITO: El Puesto ha sido eliminado permanentemente...'
CALL SP_EliminarPuestoFisico(@IdPuesto1);

-- 5.4. Eliminación Física Exitosa - Puesto 2
CALL SP_EliminarPuestoFisico(@IdPuesto2);

/* =================================================================================
   FIN DE LAS PRUEBAS - MÓDULO PUESTOS
   Si pasaste los errores rojos controlados, el módulo es seguro.
   ================================================================================= */