local Checker = {}

function Checker.IsArgumentDataTypeValid(value: any): boolean
	local valueType = typeof(value)

	if valueType == "number" then
		if value ~= value then
			warn("Checker: Value is NaN (Not a Number)")
			return false
		end

		if value == math.huge or value == -math.huge then
			warn("Checker: Value is Infinity")
			return false
		end

		return true
	end

	if valueType == "Instance" then
		warn("Checker: Value is an Instance (Not allowed in this context)")
		return false
	end

	if valueType == "function" then
		warn("Checker: Value is a Function")
		return false
	end

	if valueType == "thread" then
		warn("Checker: Value is a Thread")
		return false
	end

	return true
end

function Checker.IsArgumentObjValid(obj: any, targetClassName: string?): boolean
	if typeof(obj) ~= "Instance" then
		warn("Checker: Object is not an Instance. Got: " .. typeof(obj))
		return false
	end

	if obj.Parent == nil and obj ~= game then
		warn("Checker: Object is not parented (Possibly destroyed or new)")
	end

	if targetClassName then
		if not obj:IsA(targetClassName) then
			warn(string.format("Checker: Object is a %s, expected %s", obj.ClassName, targetClassName))
			return false
		end
	end

	return true
end

return Checker