SeaMAdminPermissions = {}

local function addRolePermissions(roleName, output, visiting)
    local role = Config.Roles[roleName]
    if not role or visiting[roleName] then return end
    visiting[roleName] = true
    if role.inherits then addRolePermissions(role.inherits, output, visiting) end
    for _, permission in ipairs(role.permissions or {}) do
        output[permission] = true
    end
end

function SeaMAdminPermissions.ForRole(roleName)
    local output = {}
    addRolePermissions(roleName, output, {})
    return output
end

function SeaMAdminPermissions.Has(roleName, permission)
    local permissions = SeaMAdminPermissions.ForRole(roleName)
    return permissions['*'] == true or permissions[permission] == true
end

function SeaMAdminPermissions.PublicRoles()
    local roles = {}
    for name, role in pairs(Config.Roles) do
        roles[#roles + 1] = {
            name = name,
            label = role.label,
            color = role.color,
            permissions = SeaMAdminPermissions.ForRole(name)
        }
    end
    table.sort(roles, function(a, b) return a.label < b.label end)
    return roles
end

