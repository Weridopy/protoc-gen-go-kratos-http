{{$svrType := .ServiceType}}
{{$svrName := .ServiceName}}

{{- range .MethodSets}}
const Operation{{$svrType}}{{.OriginalName}} = "/{{$svrName}}/{{.OriginalName}}"
{{- end}}

type {{.ServiceType}}HTTPServer interface {
{{- range .MethodSets}}
	{{- if ne .Comment ""}}
	{{.Comment}}
	{{- end}}
	{{.Name}}(context.Context, *{{.Request}}) (*{{.Reply}}, error)
{{- end}}
}

{{- range .MiddlewareNames }}
    type {{$svrType}}{{.}}Middleware middleware.Middleware
{{- end}}

func New{{$svrType}}HTTPServerMiddleware(
    {{- range .MiddlewareNames }}
        {{.}} {{$svrType}}{{.}}Middleware,
    {{- end}}
) middleware.Middleware {
    return selector.Server(
    {{- range .MethodSets }}
        selector.Server(
            {{- range .MiddlewareNames }}
                middleware.Middleware({{.}}),
            {{- end}}
        ).Path(Operation{{$svrType}}{{.OriginalName}}).Build(),
    {{- end}}
    ).Path(
    {{- range .MethodSets }}
        Operation{{$svrType}}{{.OriginalName}},
    {{- end}}
    ).Build()
}

func Register{{.ServiceType}}HTTPServer(s *http.Server, srv {{.ServiceType}}HTTPServer) {
	r := s.Route("/")
	{{- range .Methods}}
	r.{{.Method}}("{{.Path}}", _{{$svrType}}_{{.Name}}{{.Num}}_HTTP_Handler(srv))
	{{- end}}
}

func Generate{{.ServiceType}}HTTPServerRouteInfo() []route.Route {
    routes := make([]route.Route, 0, {{ .Methods | len }})
	{{- range .Methods}}
	routes = append(routes, route.Route{
        Method: "{{.Method}}",
        Path: "{{.Path}}",
        Comment: "{{.LeadingComment}}",
	})
	{{- end}}
	return routes
}

{{range .Methods}}
func _{{$svrType}}_{{.Name}}{{.Num}}_HTTP_Handler(srv {{$svrType}}HTTPServer) func(ctx http.Context) error {
	return func(ctx http.Context) error {
		stdCtx := kcontext.SetKHTTPContextWithContext(ctx, ctx)
		var in {{.Request}}
		{{- if .HasBody}}
		if err := ctx.Bind(&in{{.Body}}); err != nil {
			return err
		}
		{{- end}}
		if err := ctx.BindQuery(&in); err != nil {
			return err
		}
		{{- if .HasVars}}
		if err := ctx.BindVars(&in); err != nil {
			return err
		}
		{{- end}}
		http.SetOperation(ctx,Operation{{$svrType}}{{.OriginalName}})

		{{- if .HasAudit}}
        auditRule := audit.NewAudit(
            "{{.Audit.Module}}",
            "{{.Audit.Action}}",
            []audit.Meta{
                {{- range .Audit.Metas}}
                {
                    Key: "{{.Key}}",
                    Value: audit.MetaValue{
                        {{- if .Value.Extract}}
                        Extract: "{{.Value.Extract}}",
                        {{- end}}
                        {{- if .Value.Const}}
                        Const: "{{.Value.Const}}",
                        {{- end}}
                    },
                },
                {{- end}}
            },
        )
        auditInfo, err := audit.ExtractFromRequest(ctx.Request(), auditRule)
        if err != nil {
            return err
        }
		stdCtx = kcontext.SetKHTTPAuditContextWithContext(stdCtx, auditInfo)

        {{- end}}

		h := ctx.Middleware(func(ctx context.Context, req interface{}) (interface{}, error) {
			return srv.{{.Name}}(ctx, req.(*{{.Request}}))
		})
		out, err := h(stdCtx, &in)
		if err != nil {
			return err
		}
		reply := out.(*{{.Reply}})
		return ctx.Result(200, reply{{.ResponseBody}})
	}
}
{{end}}

type {{.ServiceType}}HTTPClient interface {
{{- range .MethodSets}}
	{{.Name}}(ctx context.Context, req *{{.Request}}, opts ...http.CallOption) (rsp *{{.Reply}}, err error)
{{- end}}
}

type {{.ServiceType}}HTTPClientImpl struct{
	cc *http.Client
}

func New{{.ServiceType}}HTTPClient (client *http.Client) {{.ServiceType}}HTTPClient {
	return &{{.ServiceType}}HTTPClientImpl{client}
}

{{range .MethodSets}}
func (c *{{$svrType}}HTTPClientImpl) {{.Name}}(ctx context.Context, in *{{.Request}}, opts ...http.CallOption) (*{{.Reply}}, error) {
	var out {{.Reply}}
	pattern := "{{.Path}}"
	path := binding.EncodeURL(pattern, in, {{not .HasBody}})
	opts = append(opts, http.Operation(Operation{{$svrType}}{{.OriginalName}}))
	opts = append(opts, http.PathTemplate(pattern))
	{{if .HasBody -}}
	err := c.cc.Invoke(ctx, "{{.Method}}", path, in{{.Body}}, &out{{.ResponseBody}}, opts...)
	{{else -}}
	err := c.cc.Invoke(ctx, "{{.Method}}", path, nil, &out{{.ResponseBody}}, opts...)
	{{end -}}
	if err != nil {
		return nil, err
	}
	return &out, nil
}
{{end}}
