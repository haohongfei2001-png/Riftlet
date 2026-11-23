const demo = document.querySelector('.demo')
const thumbnail = demo.querySelector('.edge')
const added = demo.querySelector('.new')
const draft = demo.querySelector('textarea')
const statusText = demo.querySelector('#state')
const reset = demo.querySelector('.reset')
const originalText = draft.value

thumbnail.addEventListener('click', () => {
  if (!added.hidden) return
  added.hidden = false
  demo.classList.add('attached')
  thumbnail.disabled = true
  statusText.textContent = demo.dataset.done
  draft.focus({preventScroll: true})
})

reset.addEventListener('click', () => {
  demo.classList.remove('attached')
  draft.value = originalText
  added.hidden = true
  thumbnail.disabled = false
  statusText.textContent = demo.dataset.start
  thumbnail.focus({preventScroll: true})
})
