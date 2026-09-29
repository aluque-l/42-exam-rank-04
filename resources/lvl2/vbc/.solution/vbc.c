#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>

typedef struct node {
    enum {
        ADD,
        MULTI,
        VAL
    }   type;
    int val;
    struct node *l;
    struct node *r;
}   node;

node    *new_node(node n)
{
    node *ret = calloc(1, sizeof(n));
    if (!ret)
        return (NULL);
    *ret = n;
    return (ret);
}

void    destroy_tree(node *n)
{
    if (!n)
        return ;
    if (n->type != VAL)
    {
        destroy_tree(n->l);
        destroy_tree(n->r);
    }
    free(n);
}

void    unexpected(char c)
{
    if (c)
        printf("Unexpected token '%c'\n", c);
    else
        printf("Unexpected end of input\n");
}

int accept(char **s, char c)
{
    if (**s == c)
    {
        (*s)++;
        return (1);
    }
    return (0);
}

int expect(char **s, char c)
{
    if (accept(s, c))
        return (1);
    unexpected(**s);
    return (0);
}

node	*expr(char **s);
node	*term(char **s);
node	*factor(char **s);

node	*factor(char **s)
{
    node    *ret;

    if (isdigit(**s))
    {
        ret = new_node((node){.type = VAL, .val = **s - '0'});
        (*s)++;
        return (ret);
    }
    if (accept(s, '('))
    {
        ret = expr(s);
        if (!ret || !expect(s, ')'))
        {
            destroy_tree(ret);
            return (NULL);
        }
        return (ret);
    }
    unexpected(**s);
    return (NULL);
}

node    *term(char **s)
{
    node    *ret = factor(s);
    node    *rhs;

    while (ret && accept(s, '*'))
    {
        if (!(rhs = factor(s)))
        {
            destroy_tree(ret);
            return (NULL);
        }
        if (!(ret = new_node((node){.type = MULTI, .l = ret, .r = rhs})))
        {
            destroy_tree(rhs);
            return (NULL);
        }
    }
    return (ret);
}

node    *expr(char **s)
{
    node    *ret = term(s);
    node    *rhs;

    while (ret && accept(s, '+'))
    {
        if (!(rhs = term(s)))
        {
            destroy_tree(ret);
            return (NULL);
        }
        if (!(ret = new_node((node){.type = ADD, .l = ret, .r = rhs})))
        {
            destroy_tree(rhs);
            return (NULL);
        }
    }
    return (ret);
}

node    *parse_expr(char *s)
{
    node	*ret = expr(&s);

    if (ret && *s)
    {
        unexpected(*s);
        destroy_tree(ret);
        return (NULL);
    }
    return (ret);
}

int eval_tree(node *tree)
{
    switch (tree->type)
    {
        case ADD:
            return (eval_tree(tree->l) + eval_tree(tree->r));
        case MULTI:
            return (eval_tree(tree->l) * eval_tree(tree->r));
        case VAL:
            return (tree->val);
    }
    return (0);
}

int main(int argc, char **argv)
{
    if (argc != 2)
        return (1);
    node *tree = parse_expr(argv[1]);
    if (!tree)
        return (1);
    printf("%d\n", eval_tree(tree));
    destroy_tree(tree);
    return(0);
}
