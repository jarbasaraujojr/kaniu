const params = new URLSearchParams(window.location.search);
const animalId = params.get("id");

let currentAnimal = null;

// Carrega dados básicos do animal
async function loadAnimal() {
  const res = await fetch(`/api/animals/${animalId}`);
  if (!res.ok) {
    document.getElementById("animal-details").innerHTML = "<p>Erro ao carregar animal.</p>";
    return;
  }

  const animal = await res.json();
  currentAnimal = animal;

  document.getElementById("animal-photo").src = animal.foto;
  document.getElementById("animal-photo").alt = `Foto de ${animal.nome}`;
  document.getElementById("animal-nome").textContent = animal.nome;

  document.getElementById("animal-details").innerHTML = `
    <div class="detail-item"><strong>Espécie:</strong> <span>${animal.especie}</span></div>
    <div class="detail-item"><strong>Raça:</strong> <span>${animal.raca}</span></div>
    <div class="detail-item"><strong>Sexo:</strong> <span>${animal.sexo}</span></div>
    <div class="detail-item"><strong>Porte:</strong> <span>${animal.porte}</span></div>
    <div class="detail-item"><strong>Cor:</strong> <span>${animal.cor}</span></div>
    <div class="detail-item"><strong>Pelagem:</strong> <span>${animal.pelagem}</span></div>
    <div class="detail-item"><strong>Faixa Etária:</strong> <span>${animal.faixa_etaria}</span></div>
  `;
}

// Inicializa tabs
function initTabs() {
  const tabButtons = document.querySelectorAll(".tab-btn");
  tabButtons.forEach(btn => {
    btn.addEventListener("click", async () => {
      document.querySelectorAll(".tab-btn").forEach(b => b.classList.remove("active"));
      document.querySelectorAll(".tab-content").forEach(c => c.classList.remove("active"));

      btn.classList.add("active");
      const tabId = btn.dataset.tab;
      document.getElementById("tab-" + tabId).classList.add("active");

      // Importa subcódigo da aba
      const module = await import(`./tabs/${tabId}.js`);
      module.load(animalId);
    });
  });

  // Carrega a primeira aba automaticamente
  import("./tabs/resumo.js").then(m => m.load(animalId));
}

document.addEventListener("DOMContentLoaded", () => {
  loadAnimal();
  initTabs();
});
