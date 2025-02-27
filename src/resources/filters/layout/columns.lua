-- columns.lua
-- Copyright (C) 2021-2022 Posit Software, PBC


kSideCaptionClass = 'margin-caption'

function columns() 
  
  return {

    Div = function(el)  
      -- for any top level divs, render then
      renderDivColumn(el)
      return el      
    end,

    Span = function(el)
      -- a span that should be placed in the margin
      if _quarto.format.isLatexOutput() and hasMarginColumn(el) then 
        noteHasColumns()
        tprepend(el.content, {latexBeginSidenote(false)})
        tappend(el.content, {latexEndSidenote(el, false)})
        return el
      else 
        -- convert the aside class to a column-margin class
        if el.classes and tcontains(el.classes, 'aside') then
          noteHasColumns()
          el.classes = el.classes:filter(function(attr) 
            return attr ~= "aside"
          end)
          tappend(el.classes, {'column-margin'})
          return el
        end
      end
    end,

    RawBlock = function(el) 
      -- Implements support for raw <aside> tags and replaces them with
      -- our raw latex representation
      if _quarto.format.isLatexOutput() then
        if el.format == 'html' then
          if el.text == '<aside>' then 
            noteHasColumns()
            el = latexBeginSidenote()
          elseif el.text == '</aside>' then
            el = latexEndSidenote(el)
          end
        end
      end
      return el
    end
  }
end

function renderDivColumn(el) 

  -- for html output that isn't reveal...
  if _quarto.format.isHtmlOutput() and not _quarto.format.isHtmlSlideOutput() then

    -- For HTML output, note that any div marked an aside should
    -- be marked a column-margin element (so that it is processed 
    -- by post processors). 
    -- For example: https://github.com/quarto-dev/quarto-cli/issues/2701
    if el.classes and tcontains(el.classes, 'aside') then
      noteHasColumns()
      el.classes = el.classes:filter(function(attr) 
        return attr ~= "aside"
      end)
      tappend(el.classes, {'column-margin'})
      return el
    end

  elseif el.identifier and el.identifier:find("^lst%-") then
    -- for listings, fetch column classes from sourceCode element
    -- and move to the appropriate spot (e.g. caption, container div)
    local captionEl = el.content[1]
    local codeEl = el.content[2]
    
    if captionEl and codeEl then
      local columnClasses = resolveColumnClasses(codeEl)
      if #columnClasses > 0 then
        noteHasColumns()
        removeColumnClasses(codeEl)

        for i, clz in ipairs(columnClasses) do 
          if clz == kSideCaptionClass and _quarto.format.isHtmlOutput() then
            -- wrap the caption if this is a margin caption
            -- only do this for HTML output since Latex captions typically appear integrated into
            -- a tabular type layout in latex documents
            local captionContainer = pandoc.Div({captionEl}, pandoc.Attr("", {clz}))
            el.content[1] = codeEl
            el.content[2] = captionContainer    
          else
            -- move to container
            el.classes:insert(clz)
          end
        end
      end
    end

  elseif _quarto.format.isLatexOutput() and not requiresPanelLayout(el) then

    -- see if there are any column classes
    local columnClasses = resolveColumnClasses(el)
    if #columnClasses > 0 then
      noteHasColumns() 
      
      if el.classes:includes('cell-output-display') and #el.content > 0 then
        -- this could be a code-display-cell
        local figOrTable = false
        local floatRefTarget = false
        for j=1,#el.content do
          local contentEl = el.content[j]

          -- wrap figures
          local figure = discoverFigure(contentEl, false)
          if figure ~= nil then
            applyFigureColumns(columnClasses, figure)
            figOrTable = true
          elseif contentEl.t == 'Div' and hasTableRef(contentEl) then
            -- wrap table divs
            latexWrapEnvironment(contentEl, latexTableEnv(el), false)
            figOrTable = true
          elseif contentEl.attr ~= nil and hasFigureRef(contentEl) then
            -- wrap figure divs
            latexWrapEnvironment(contentEl, latexFigureEnv(el), false)
            figOrTable = true
          elseif contentEl.t == 'Table' then
            -- wrap the table in a div and wrap the table environment around it
            local tableDiv = pandoc.Div({contentEl})
            latexWrapEnvironment(tableDiv, latexTableEnv(el), false)
            el.content[j] = tableDiv
            figOrTable = true
          elseif contentEl.t == 'Div' then
            -- forward the columns class from the output div
            -- onto the float ref target, which prevents
            -- the general purpose `sidenote` processing from capturing this
            -- element (since floats know how to deal with margin positioning)
            local custom = _quarto.ast.resolve_custom_data(contentEl)
            if custom ~= nil then  
              floatRefTarget = true
              removeColumnClasses(el)
              addColumnClasses(columnClasses, custom)
            end
          end 
        end

        if not figOrTable and not floatRefTarget then
          processOtherContent(el.content)
        end
      else

        
        -- this is not a code cell so process it
        if el.attr ~= nil then
          if hasTableRef(el) then
            latexWrapEnvironment(el, latexTableEnv(el), false)
          elseif hasFigureRef(el) then
            latexWrapEnvironment(el, latexFigureEnv(el), false)
          else
            -- Look in the div to see if it contains a figure
            local figure = nil
            for j=1,#el.content do
              local contentEl = el.content[j]
              if figure == nil then
                figure = discoverFigure(contentEl, false)
              end
            end
            if figure ~= nil then
              applyFigureColumns(columnClasses, figure)
            else
              processOtherContent(el)
            end
          end
        end
      end   
    else 
       -- Markup any captions for the post processor
      latexMarkupCaptionEnv(el);
    end
  end
end

function processOtherContent(el)
  if hasMarginColumn(el) then
    -- (margin notes)
    noteHasColumns()
    tprepend(el.content, {latexBeginSidenote()});
    tappend(el.content, {latexEndSidenote(el)})
  else 
    -- column classes, but not a table or figure, so 
    -- handle appropriately
    local otherEnv = latexOtherEnv(el)
    if otherEnv ~= nil then
      latexWrapEnvironment(el, otherEnv, false)
    end
  end
  removeColumnClasses(el)
end

function applyFigureColumns(columnClasses, figure)
  -- just ensure the classes are - they will be resolved
  -- when the latex figure is rendered
  addColumnClasses(columnClasses, figure)

  -- ensure that extended figures will render this
  forceExtendedFigure(figure)  
end
  

function hasColumnClasses(el) 
  return tcontains(el.classes, isColumnClass) or hasMarginColumn(el)
end

function hasMarginColumn(el)
  if el.classes ~= nil then
    return tcontains(el.classes, 'column-margin') or tcontains(el.classes, 'aside')
  else
    return false
  end
end

function hasMarginCaption(el)
  if el.classes ~= nil then
    return tcontains(el.classes, 'margin-caption')
  else
    return false
  end
end

function noteHasColumns() 
  layoutState.hasColumns = true
end

function notColumnClass(clz) 
  return not isColumnClass(clz)
end

function resolveColumnClasses(el) 
  return el.classes:filter(isColumnClass)
end

function columnToClass(column)
  if column ~= nil then
    return 'column-' .. column[1].text
  else
    return nil
  end
end

function removeColumnClasses(el)
  if el.classes then
    for i, clz in ipairs(el.classes) do 
      if isColumnClass(clz) then
        el.classes:remove(i)
      end
    end  
  end
end

function addColumnClasses(classes, toEl) 
  removeColumnClasses(toEl)
  for i, clz in ipairs(classes) do 
    if isColumnClass(clz) then
      toEl.classes:insert(clz)
    end
  end  
end

function removeCaptionClasses(el)
  for i, clz in ipairs(el.classes) do 
    if isCaptionClass(clz) then
      el.classes:remove(i)
    end
  end
end

function resolveCaptionClasses(el)
  local filtered = el.classes:filter(isCaptionClass)
  if #filtered > 0 then
    return {'margin-caption'}
  else
    -- try looking for attributes
    if el.attributes ~= nil and el.attributes['cap-location'] == "margin" then
      return {'margin-caption'}
    else
      return {}
    end
  end
end

function isCaptionClass(clz)
  return clz == 'caption-margin' or clz == 'margin-caption'
end

function isColumnClass(clz) 
  if clz == nil then
    return false
  elseif clz == 'aside' then
    return true
  else
    return clz:match('^column%-')
  end
end