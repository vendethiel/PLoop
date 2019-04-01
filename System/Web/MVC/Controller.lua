--===========================================================================--
--                                                                           --
--                      System.Web.Controller                      --
--                                                                           --
--===========================================================================--

--===========================================================================--
-- Author       :   kurapica125@outlook.com                                  --
-- URL          :   http://github.com/kurapica/PLoop                         --
-- Create Date  :   2015/06/10                                               --
-- Update Date  :   2019/04/01                                               --
-- Version      :   1.1.0                                                    --
--===========================================================================--

PLoop(function(_ENV)
    export {
        getmetatable            = getmetatable,
        strlower                = string.lower,
        safeset                 = Toolset.safeset,

        Enum, HttpMethod,

        -- Declare global variables
        saveActionMap           = false,
        getActionMap            = false,
    }

    local _HttpMethodMap        = {}

    function saveActionMap(owner, name, action, method)
        local map               = _HttpMethodMap[owner]
        if not map then
            map                 = {}
            _HttpMethodMap      = safeset(_HttpMethodMap, owner, map)
        end

        action                  = strlower(action)

        -- Record it
        map[action]             = map[action] or {}

        if method == HttpMethod.ALL then
            map[action][0]      = name
        else
            for _, v in Enum.Parse(HttpMethod, method) do
                map[action][v]  = name
            end
        end
    end

    function getActionMap(self, context)
        local map = _HttpMethodMap[getmetatable(self)]

        if map then
            map = self.Action and map[strlower(self.Action)]
            if map then
                return map[context.Request.HttpMethod] or map[0]
            end
        end
    end

    --- the web controller
    __Sealed__()
    __NoNilValue__(false):AsInheritable()
    __NoRawSet__  (false):AsInheritable()
    class "System.Web.Controller" (function (_ENV)
        extend (System.Web.IHttpContextHandler)
        extend (System.Web.IHttpContext)

        export {
            type                = type,
            GetRelativeResource = GetRelativeResource,
            serialize           = Serialization.Serialize,
            tostring            = tostring,
            getmetatable        = getmetatable,
            isclass             = Class.Validate,
            issubtype           = Class.IsSubType,
            ispathrooted        = IO.Path.IsPathRooted,
            getActionMap        = getActionMap,
            parseString         = ParseString,
            HEAD_PHASE          = IHttpContextHandler.ProcessPhase.Head,
            Error               = Logger.Default[Logger.LogLevel.Error],

            yield               = coroutine.yield,
            status              = coroutine.status,
            resume              = coroutine.resume,
            error               = error,

            JsonFormatProvider, IHttpOutput, HTTP_STATUS, IHttpContextHandler.ProcessPhase,
            Controller, ThreadPool
        }

        -----------------------------------------------------------------------
        --                             property                              --
        -----------------------------------------------------------------------
        property "Action"       { type = String }

        --- The handler's process phase
        property "ProcessPhase" { type = ProcessPhase, default = ProcessPhase.Head + ProcessPhase.Body + ProcessPhase.Final }

        -----------------------------------------------------------------------
        --                              method                               --
        -----------------------------------------------------------------------
        --- Send the text as response
        -- @format  (text)
        -- @format  (iterator, obj, index)
        -- @param   text            the response text
        -- @param   iterator        the iterator used to return text
        -- @param   obj             the iterator object
        -- @param   index           the iterator index
        function Text(self, text, obj, idx)
            local res       = self.Context.Response
            if res.RequestRedirected or res.StatusCode ~= HTTP_STATUS.OK then return end

            local write     = res.Write
            res.ContentType = "text/plain"

            yield() -- finish head sending

            if type(text) == "function" then
                for i, m in text, obj, idx do write(parseString(m or i)) end
            else
                write(parseString(text))
            end

            yield() -- finish body sending
        end

        --- Render a page with data as response
        -- @param   path            the response page path
        -- @param   ...             the data that passed to the view
        function View(self, path, ...)
            local res       = self.Context.Response
            if res.RequestRedirected or res.StatusCode ~= HTTP_STATUS.OK then return end

            local context   = self.Context
            local cls       = type(path) == "string" and GetRelativeResource(self, path, context) or path

            if isclass(cls) and issubtype(cls, IHttpOutput) then
                local view  = cls(...)

                res.ContentType = "text/html"

                view.Context= context
                view:OnLoad(context)

                yield()

                view:SafeRender(res.Write, "")

                yield()
            else
                Error("%s - the view page file can't be found.", tostring(path))
                res.StatusCode = HTTP_STATUS.NOT_FOUND
            end
        end

        --- Send the json data as response
        -- @param   json            the response json
        -- @param   type            the object type to be serialized
        function Json(self, object, oType)
            local res       = self.Context.Response
            if res.RequestRedirected or res.StatusCode ~= HTTP_STATUS.OK then return end

            local context   = self.Context
            if context.IsInnerRequest then --and context.RawContext.ProcessPhase == HEAD_PHASE then
                context:SaveJsonData(object, oType)
            else
                res.ContentType = "application/json"

                yield()

                if oType then
                    serialize(JsonFormatProvider(), object, oType, res.Write)
                else
                    serialize(JsonFormatProvider(), object, res.Write)
                end

                yield()
            end
        end

        --- Redirect to another url
        -- @param   url            the redirected url
        function Redirect(self, path, raw)
            local res       = self.Context.Response
            if res.RequestRedirected then return end

            if path ~= "" then
                if not ispathrooted(path) then
                    Error("Only absolute path supported for Controller's Redirect.")
                    res.StatusCode = HTTP_STATUS.NOT_FOUND
                    return
                end
                res:Redirect(path, nil, raw)
            end
        end

        --- Missing
        function NotFound(self)
            self.Context.Response.StatusCode = HTTP_STATUS.NOT_FOUND
        end

        -----------------------------------------------------------------------
        --                          inherit method                           --
        -----------------------------------------------------------------------
        function Process(self, context, phase)
            if phase == HEAD_PHASE then
                local action = getActionMap(self, context)
                if action then
                    self.Context = context
                    local thread = ThreadPool.Current:GetThread(self[action])
                    local ok, err= resume(thread, self, context)
                    if not ok then error(err, 0) end
                    context[Controller] = thread
                else
                    context.Response.StatusCode = HTTP_STATUS.NOT_FOUND
                end
            else -- For Body & Final Phase
                local thread = context[Controller]
                if thread and status(thread) == "suspended" then
                    local ok, err= resume(thread, self, context)
                    if not ok then error(err, 0) end
                end
            end
        end
    end)

    --- the attribute to bind action to the controller
    __Sealed__() class "System.Web.__Action__" (function(_ENV)
        extend "IAttachAttribute"

        export {
            issubtype           = Class.IsSubType,
            saveActionMap       = saveActionMap,
        }
        export { Controller }

        -----------------------------------------------------------
        --                       property                        --
        -----------------------------------------------------------
        property "Method" { type = HttpMethod, default = HttpMethod.ALL }
        property "Action" { type = String }

        -----------------------------------------------------------
        --                        method                         --
        -----------------------------------------------------------
        function AttachAttribute(self, target, targettype, owner, name, stack)
            local method = self.Method
            local action = self.Action or name

            if not issubtype(owner, Controller) then return end

            saveActionMap(owner, name, self.Action or name, self.Method)
        end

        __Arguments__{ String, HttpMethod/HttpMethod.ALL }
        function __Action__(self, action, method)
            self.Action = action
            self.Method = method
        end

        __Arguments__{ HttpMethod/HttpMethod.ALL }
        function __Action__(self, method)
            self.Method = method
        end
    end)
end)