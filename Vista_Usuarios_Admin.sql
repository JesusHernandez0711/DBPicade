/* ======================================================================================================
   VIEW: Vista_Usuarios_Admin
   ======================================================================================================
   
   1. VISIÓN GENERAL Y OBJETIVO DE NEGOCIO (BUSINESS GOAL)
   -------------------------------------------------------
   Esta vista constituye la **Interfaz de Lectura Optimizada** para el Grid Principal del Módulo de 
   Administración de Usuarios.
   
   Su función es consolidar la identidad digital (`Usuarios`) y la identidad humana (`Info_Personal`) 
   en una estructura plana, ligera y lista para ser consumida por componentes de UI (Tablas/Grids).

   2. ARQUITECTURA DE DATOS (ESTRATEGIA DE INTEGRIDAD)
   ---------------------------------------------------
   - TIPO DE JOIN: Se utiliza **INNER JOIN** estricto entre las tablas `Usuarios`, `Info_Personal` y `Cat_Roles`.
   
   - JUSTIFICACIÓN TÉCNICA: 
     En la lógica de negocio del sistema PICADE, existe una relación de dependencia existencial fuerte:
     a) Un "Usuario" (Cuenta) NO puede existir sin estar vinculado a una "Persona" (Datos RH).
     b) Un "Usuario" NO puede existir sin tener asignado un "Rol de Seguridad".
     
     Por lo tanto, cualquier registro que no cumpla estas condiciones se considera "Corrupto" o "Incompleto"
     y debe ser excluido automáticamente de la lista operativa mediante el INNER JOIN.

   3. ESTRATEGIA DE PRESENTACIÓN HÍBRIDA (UX & REPORTING)
   ------------------------------------------------------
   Para satisfacer tanto los requisitos de Interfaz de Usuario (Ordenamiento) como los de Reportes (Visualización),
   esta vista expone los datos de nombres en dos formatos simultáneos:

     A) FORMATO COMPUESTO (`Nombre_Completo`):
        - Implementación: `CONCAT_WS(' ', Nombre, Paterno, Materno)`
        - Uso: Etiquetas de UI, Encabezados de Perfil y **Reportes PDF**.
        - Ventaja: Elimina la necesidad de concatenar cadenas en el Frontend o en el motor de reportes.

     B) FORMATO ATÓMICO (`Nombre`, `Apellidos`):
        - Implementación: Columnas individuales crudas.
        - Uso: Lógica de **Ordenamiento (Sort)** y **Filtrado (Filter)** en el Grid.
        - Ventaja: Permite cumplir la norma administrativa de ordenar listas por "Apellido Paterno" (A-Z)
          en lugar de por Nombre de Pila.

   4. DICCIONARIO DE DATOS (CONTRATO DE SALIDA)
   --------------------------------------------
   [Bloque 1: Identificadores de Sistema]
   - Id_Usuario:      (INT) Llave primaria (Oculta en el Grid, usada para acciones CRUD).
   - Ficha_Usuario:   (VARCHAR) Identificador corporativo único (Clave de búsqueda para Instructores).
   - Email_Usuario:   (VARCHAR) Credencial de acceso (Login).

   [Bloque 2: Identidad Personal]
   - Nombre_Completo: (VARCHAR) Nombre completo pre-calculado para visualización rápida.
   - Nombre:          (VARCHAR) Dato atómico para lógica de negocio.
   - Apellido_Paterno:(VARCHAR) Dato atómico crítico para ordenamiento de listas.
   - Apellido_Materno:(VARCHAR) Dato atómico complementario.

   [Bloque 3: Seguridad y Control]
   - Rol_Usuario:     (VARCHAR) Nombre legible del perfil de seguridad (ej: 'Administrador').
   - Estatus_Usuario: (TINYINT) Bandera de acceso: 
                        1 = Activo (Puede loguearse y ser Instructor).
                        0 = Bloqueado (Acceso denegado y oculto en selectores operativos).
   ====================================================================================================== */

-- DROP VIEW IF EXISTS `PICADE`.`Vista_Usuarios`;

CREATE OR REPLACE 
    ALGORITHM = UNDEFINED 
    SQL SECURITY DEFINER
VIEW `PICADE`.`Vista_Usuarios` AS
    SELECT
        /* -----------------------------------------------------------------------------------
           BLOQUE 1: IDENTIDAD DIGITAL (CREDENCIALES)
           Datos fundamentales para la identificación única de la cuenta.
           ----------------------------------------------------------------------------------- */
        `Usuarios`.`Id_Usuario`,
        /* NUEVO CAMPO: FOTO DE PERFIL 
           Permite mostrar una miniatura (thumbnail) en la tabla de usuarios. */
        `Usuarios`.`Foto_Perfil_Url`     AS `Foto_Perfil`,
        `Usuarios`.`Ficha`               AS `Ficha_Usuario`,
        `Usuarios`.`Email`               AS `Email_Usuario`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 2: IDENTIDAD HUMANA (DATOS PERSONALES - ESTRATEGIA HÍBRIDA)
           Se exponen ambos formatos para dar flexibilidad total al Frontend y Reportes.
           ----------------------------------------------------------------------------------- */
        
        /* [FORMATO VISUAL]: Para mostrar en la celda del Grid o en Reportes PDF */         
         CONCAT_WS(' ', `Info_User`.`Nombre`, `Info_User`.`Apellido_Paterno`, `Info_User`.`Apellido_Materno`) AS `Nombre_Completo`,
        
        /* [FORMATO LÓGICO]: Para que el Grid pueda ordenar por 'Apellido_Paterno' aunque muestre el completo */
        `Info_User`.`Nombre`             AS `Nombre`,
        `Info_User`.`Apellido_Paterno`   AS `Apellido_Paterno`,
        `Info_User`.`Apellido_Materno`   AS `Apellido_Materno`,

        /* -----------------------------------------------------------------------------------
           BLOQUE 3: SEGURIDAD Y CONTROL DE ACCESO
           Información crítica para la administración de permisos y auditoría rápida.
           ----------------------------------------------------------------------------------- */
        `Roles`.`Nombre`                 AS `Rol_Usuario`,
        
        /* Mapeo Semántico: 'Activo' -> 'Estatus_Usuario'
           El Grid usará este valor para pintar el Switch (Verde/Gris) o filtrar instructores elegibles. */
        `Usuarios`.`Activo`              AS `Estatus_Usuario`

    FROM
        `PICADE`.`Usuarios` `Usuarios`
        
        /* JOIN 1: Vinculación Obligatoria con Datos Personales
           Garantiza que todo usuario listado tenga una ficha de RH válida. */
        INNER JOIN `PICADE`.`Info_Personal` `Info_User`
            ON `Usuarios`.`Fk_Id_InfoPersonal` = `Info_User`.`Id_InfoPersonal`
            
        /* JOIN 2: Vinculación Obligatoria con Roles de Seguridad
           Garantiza que se muestre el nivel de privilegios del usuario. */
        INNER JOIN `PICADE`.`Cat_Roles` `Roles`
            ON `Usuarios`.`Fk_Rol` = `Roles`.`Id_Rol`;