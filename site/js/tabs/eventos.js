export async function load(animalId) {
  const res = await fetch(`/api/animals/${animalId}/eventos`);
  const data = await res.json();

  const container = document.getElementById("tab-eventos");
  if (!data.length) {
    container.innerHTML = "<p>Nenhum evento registrado.</p>";
    return;
  }

  container.innerHTML = `
    <table class="tab-table">
      <thead>
        <tr><th>Data</th><th>Tipo</th><th>Descrição</th></tr>
      </thead>
      <tbody>
        ${data.map(ev => `
          <tr>
            <td>${ev.data}</td>
            <td>${ev.tipo}</td>
            <td>${ev.descricao}</td>
          </tr>
        `).join("")}
      </tbody>
    </table>
  `;
}
