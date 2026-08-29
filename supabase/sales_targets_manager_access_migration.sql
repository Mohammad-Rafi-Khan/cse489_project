-- Sales target manager/admin access migration
-- Scope managers to their own branch while preserving admin company-wide access.

DROP POLICY IF EXISTS "sales_targets_select" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_modify" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_select_scoped" ON public.sales_targets;
DROP POLICY IF EXISTS "sales_targets_modify_scoped" ON public.sales_targets;

CREATE POLICY "sales_targets_select_scoped" ON public.sales_targets FOR SELECT USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);

CREATE POLICY "sales_targets_modify_scoped" ON public.sales_targets FOR ALL USING (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
) WITH CHECK (
  public.get_my_role() = 'admin'
  OR (public.get_my_role() = 'manager' AND branch_id = public.get_my_branch_id())
);
